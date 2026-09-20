"""Measure executed game effects; never used by the acting agent."""

import collections, copy
import engine as E


class Audit:
    def __init__(self, farm, private):
        self.farm = farm
        self.private = private
        self.start_money = farm["money"]
        self.original = {}
        self.ledger = collections.defaultdict(lambda: {"quantity": 0, "coins": 0})
        self.production = collections.Counter()
        self.harvests = collections.Counter()
        self.noops = collections.Counter()
        self.losses = collections.Counter()

        def unit(original, farm, private, idx, action, *args, **kwargs):
            if farm is not self.farm:
                return original(farm, private, idx, action, *args, **kwargs)
            p = E._farmer_position(farm, idx)
            if p is None:
                return original(farm, private, idx, action, *args, **kwargs)
            x, y = p
            before = copy.deepcopy(farm["tiles"][y][x])
            inv = private["inventories"][idx].copy()
            old = (copy.deepcopy(p), before, copy.deepcopy(private))
            result = original(farm, private, idx, action, *args, **kwargs)
            if old == (E._farmer_position(farm, idx), farm["tiles"][y][x], private):
                self.noops[action[0]] += 1
            if action[0] in ["HARVEST", "COLLECT_FERTILIZER"]:
                for k, v in private["inventories"][idx].items():
                    gain = v - inv.get(k, 0)
                    if gain > 0:
                        self.production[k] += gain
                        if action[0] == "HARVEST":
                            day = args[1]
                            age = day - before.get(
                                "planted_day", before.get("placed_day", day)
                            )
                            self.harvests[f"{k}:age{age}:yield{gain}"] += 1
            return result

        def commit(original, op, item, price, farm, *args, **kwargs):
            ok = original(op, item, price, farm, *args, **kwargs)
            if ok and farm is self.farm:
                row = self.ledger[f"{op}:{item}"]
                row["quantity"] += 1
                row["coins"] += price
            return ok

        def purchase(original, label, farm, *args, **kwargs):
            before = farm["money"]
            out = original(farm, *args, **kwargs)
            if farm is self.farm and farm["money"] != before:
                row = self.ledger[label]
                row["quantity"] += 1
                row["coins"] += before - farm["money"]
            return out

        def refresh(original, farm, *args, **kwargs):
            before = copy.deepcopy(farm["tiles"]) if farm is self.farm else None
            out = original(farm, *args, **kwargs)
            if before is not None:
                for y, row in enumerate(before):
                    for x, t in enumerate(row):
                        if not isinstance(t, dict):
                            continue
                        after = farm["tiles"][y][x]
                        if "animal" in t and (
                            not isinstance(after, dict) or "animal" not in after
                        ):
                            self.losses["escaped_" + t["animal"]] += 1
                        if (
                            t.get("kind") == "PLANT"
                            and isinstance(after, dict)
                            and after.get("kind") == "WEED"
                        ):
                            self.losses["drought_" + t["crop"]] += 1
            return out

        def drop(original, private, capacity):
            before = sum(private["shed"].values()) + sum(
                sum(inv.values()) for inv in private["inventories"]
            )
            out = original(private, capacity)
            if private is self.private:
                self.losses["overflow_units"] += before - sum(private["shed"].values())
            return out

        self.install("_apply_unit_action", unit)
        self.install("_commit_unit", commit)
        self.install(
            "_do_hire",
            lambda original, *a, **k: purchase(original, "HIRE:HAND", *a, **k),
        )
        self.install(
            "_do_buy_land",
            lambda original, *a, **k: purchase(original, "BUY_LAND:LAND", *a, **k),
        )
        self.install("_daily_refresh_plants", refresh)
        self.install("_daily_refresh_animals", refresh)
        self.install("_drop_inventories_to_shed", drop)

    def install(self, name, wrapper):
        original = getattr(E, name)
        self.original[name] = original
        setattr(E, name, lambda *args, **kwargs: wrapper(original, *args, **kwargs))

    def close(self):
        for name, original in self.original.items():
            setattr(E, name, original)
        income = sum(
            v["coins"] for k, v in self.ledger.items() if k.startswith("SELL:")
        )
        cost = sum(
            v["coins"] for k, v in self.ledger.items() if not k.startswith("SELL:")
        )
        assert self.start_money + income - cost == self.farm["money"], (
            self.start_money,
            income,
            cost,
            self.farm["money"],
        )
        return {
            "income": income,
            "cost": cost,
            "ledger": dict(self.ledger),
            "production": dict(self.production),
            "harvests": dict(self.harvests),
            "noops": dict(self.noops),
            "losses": dict(self.losses),
            "cash_identity_verified": True,
        }
