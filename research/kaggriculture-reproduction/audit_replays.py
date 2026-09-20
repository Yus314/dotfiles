"""Audit public replays by executing the published engine and tracing its effects.

No competitor source code is executed. All actions are recorded public actions.
Index t refers to the decision at observation t, stored in replay state t + 1.
"""

import ast
import argparse
import collections
import copy
import csv
import gzip
import hashlib
import json
import pathlib
import types

from fetch_data import DEFAULT_DATA

ROOT = DEFAULT_DATA
SUBMISSION = 56216119


class Node(dict):
    def __getattr__(self, key):
        try:
            return self[key]
        except KeyError as e:
            raise AttributeError(key) from e

    def __setattr__(self, key, value):
        self[key] = value


def node(x):
    if isinstance(x, dict):
        return Node({k: node(v) for k, v in x.items()})
    if isinstance(x, list):
        return [node(v) for v in x]
    return x


def load_engine():
    source = pathlib.Path(__file__).parent / "engine.py"
    tree = ast.parse(source.read_text())
    # Seed resolution is used only for initialization. Replays contain an already
    # initialized state and resolved seed; no kaggle-environments installation
    # is needed to execute the unchanged transition functions.
    tree.body = [
        x
        for x in tree.body
        if not (
            isinstance(x, ast.ImportFrom) and x.module == "kaggle_environments.utils"
        )
    ]
    mod = types.ModuleType("audited_engine")
    mod.__file__ = str(source)
    exec(compile(tree, str(source), "exec"), mod.__dict__)
    return mod


def tile_counts(farm):
    return dict(
        collections.Counter(
            t.get("crop", t.get("animal", t.get("kind")))
            for row in farm["tiles"]
            for t in row
            if isinstance(t, dict)
        )
    )


def audit(entry):
    eid = entry["id"]
    raw = gzip.decompress((ROOT / f"episode-{eid}.json.gz").read_bytes())
    replay = json.loads(raw)
    assert replay["info"]["EpisodeId"] == eid
    target = next(
        a.get("index", 0) for a in entry["agents"] if a["submissionId"] == SUBMISSION
    )
    engine = load_engine()
    state = node(copy.deepcopy(replay["steps"][0]))
    env = Node(
        configuration=node(replay["configuration"]),
        info=node(replay["info"]),
        done=False,
    )
    farms = state[0].observation.farms
    farm_ids = {id(f): i for i, f in enumerate(farms)}
    units, orders, losses, days = [], [], [], []
    requested = [collections.Counter(), collections.Counter()]
    timer = {"step": 0}
    original_unit = engine._apply_unit_action
    original_commit = engine._commit_unit
    original_hire = engine._do_hire
    original_land = engine._do_buy_land
    original_refresh_plants = engine._daily_refresh_plants
    original_refresh_animals = engine._daily_refresh_animals
    original_drop = engine._drop_inventories_to_shed

    def unit(farm, private, idx, action, *args, **kwargs):
        pid = farm_ids[id(farm)]
        pos = engine._farmer_position(farm, idx)
        if pos is None:
            return original_unit(farm, private, idx, action, *args, **kwargs)
        x, y = pos
        before = copy.deepcopy(farm["tiles"][y][x])
        inv = copy.deepcopy(private["inventories"][idx])
        relevant = (copy.deepcopy(pos), before, copy.deepcopy(private))
        original_unit(farm, private, idx, action, *args, **kwargs)
        changed = relevant != (
            engine._farmer_position(farm, idx),
            farm["tiles"][y][x],
            private,
        )
        t = before if isinstance(before, dict) else {}
        gain = {
            k: v - inv.get(k, 0)
            for k, v in private["inventories"][idx].items()
            if v > inv.get(k, 0)
        }
        units.append(
            {
                "step": timer["step"],
                "day": timer["step"] // 24,
                "hour": timer["step"] % 24,
                "seat": pid,
                "unit": idx,
                "action": action,
                "x": x,
                "y": y,
                "kind": t.get("kind"),
                "item": t.get("crop", t.get("animal")),
                "age": timer["step"] // 24
                - t.get("planted_day", t.get("placed_day", timer["step"] // 24)),
                "yield": t.get("yield_units"),
                "fertilized_until": t.get("fertilized_until_day"),
                "watered": t.get("watered_today"),
                "fed": t.get("fed_today"),
                "cared": t.get("cared_today"),
                "consecutive_unfed": t.get("consecutive_unfed"),
                "changed": changed,
                "gains": gain,
            }
        )

    def commit(op, item, price, farm, *args, **kwargs):
        ok = original_commit(op, item, price, farm, *args, **kwargs)
        if ok:
            orders.append(
                {
                    "step": timer["step"],
                    "seat": farm_ids[id(farm)],
                    "op": op,
                    "item": item,
                    "price": price,
                }
            )
        return ok

    def hire(farm, *args, **kwargs):
        before = farm["money"]
        original_hire(farm, *args, **kwargs)
        if before != farm["money"]:
            orders.append(
                {
                    "step": timer["step"],
                    "seat": farm_ids[id(farm)],
                    "op": "HIRE",
                    "item": "HAND",
                    "price": before - farm["money"],
                }
            )

    def land(farm, *args, **kwargs):
        before = farm["money"]
        original_land(farm, *args, **kwargs)
        if before != farm["money"]:
            orders.append(
                {
                    "step": timer["step"],
                    "seat": farm_ids[id(farm)],
                    "op": "BUY_LAND",
                    "item": farm["unlocked_quadrants"][-1],
                    "price": before - farm["money"],
                }
            )

    def refresh(farm, fn, label, *args):
        before = copy.deepcopy(farm["tiles"])
        fn(farm, *args)
        for y, row in enumerate(before):
            for x, tile in enumerate(row):
                if not isinstance(tile, dict):
                    continue
                after = farm["tiles"][y][x]
                if "animal" in tile and "animal" not in after:
                    losses.append(
                        {
                            "step": timer["step"],
                            "seat": farm_ids[id(farm)],
                            "type": "animal_escape",
                            "x": x,
                            "y": y,
                            "tile": tile,
                        }
                    )
                if tile.get("kind") == "PLANT" and after.get("kind") == "WEED":
                    losses.append(
                        {
                            "step": timer["step"],
                            "seat": farm_ids[id(farm)],
                            "type": "drought",
                            "x": x,
                            "y": y,
                            "tile": tile,
                        }
                    )

    def drop(private, capacity):
        before = sum(private["shed"].values()) + sum(
            sum(i.values()) for i in private["inventories"]
        )
        original_drop(private, capacity)
        after = sum(private["shed"].values())
        if before > after:
            pid = next(
                i for i, s in enumerate(state) if s.observation.private is private
            )
            losses.append(
                {
                    "step": timer["step"],
                    "seat": pid,
                    "type": "shed_overflow",
                    "quantity": before - after,
                }
            )

    engine._apply_unit_action = unit
    engine._commit_unit = commit
    engine._do_hire = hire
    engine._do_buy_land = land
    engine._daily_refresh_plants = lambda farm, *args: refresh(
        farm, original_refresh_plants, "plants", *args
    )
    engine._daily_refresh_animals = lambda farm, *args: refresh(
        farm, original_refresh_animals, "animals", *args
    )
    engine._drop_inventories_to_shed = drop

    for t in range(len(replay["steps"]) - 1):
        timer["step"] = t
        for pid in range(2):
            state[pid].observation.step = t
            state[pid].action = node(replay["steps"][t + 1][pid]["action"])
            a = state[pid].action
            for act in [a.get("farmer", ["PASS"])] + a.get("hands", []):
                key = (
                    ":".join(str(s) for s in act[:2])
                    if act[0] in ("PLANT", "PLACE", "PICKUP")
                    else act[0]
                )
                requested[pid][key] += 1
        engine.interpreter(state, env)
        for pid in range(2):
            actual = state[pid].observation
            expected = replay["steps"][t + 1][pid]["observation"]
            for key in ("farms", "private", "market", "town", "day", "hour"):
                if actual[key] != expected[key]:
                    raise AssertionError(
                        f"Episode {eid} decision {t} seat {pid}: {key} mismatch"
                    )
        if (t + 1) % 24 == 0 or t == len(replay["steps"]) - 2:
            # The state at 24*(d+1) has completed the refresh of day d.
            for pid in range(2):
                farm = farms[pid]
                days.append(
                    {
                        "day": t // 24,
                        "seat": pid,
                        "money": farm["money"],
                        "counts": tile_counts(farm),
                        "prices": dict(state[0].observation.market["prices"]),
                        "shops": list(state[0].observation.town["unlocked_shops"]),
                        "shed": dict(state[pid].observation.private["shed"]),
                    }
                )

    player_summaries = []
    for pid in range(2):
        ps = {
            "seat": pid,
            "name": replay["info"]["TeamNames"][pid],
            "requested_actions": dict(requested[pid]),
        }
        player_orders = [o for o in orders if o["seat"] == pid]
        player_units = [u for u in units if u["seat"] == pid]
        totals = {}
        for o in player_orders:
            k = f"{o['op']}:{o['item']}"
            totals.setdefault(k, {"quantity": 0, "coins": 0})
            totals[k]["quantity"] += 1
            totals[k]["coins"] += o["price"]
        income = sum(o["price"] for o in player_orders if o["op"] == "SELL")
        cost = sum(o["price"] for o in player_orders if o["op"] != "SELL")
        assert env.configuration.startingMoney + income - cost == replay["rewards"][pid]
        ps.update(
            {
                "final_money": replay["rewards"][pid],
                "income": income,
                "cost": cost,
                "ledger": totals,
                "land": [o for o in player_orders if o["op"] == "BUY_LAND"],
                "losses": [l for l in losses if l["seat"] == pid],
                "effective_actions": dict(
                    collections.Counter(
                        u["action"][0] for u in player_units if u["changed"]
                    )
                ),
                "noops": dict(
                    collections.Counter(
                        u["action"][0] for u in player_units if not u["changed"]
                    )
                ),
                "fertilized_crops": dict(
                    collections.Counter(
                        u["item"]
                        for u in player_units
                        if u["action"][0] == "FERTILIZE" and u["changed"]
                    )
                ),
                "harvests": dict(
                    collections.Counter(
                        u["item"]
                        for u in player_units
                        if u["action"][0] == "HARVEST" and u["changed"]
                    )
                ),
                "final_private": replay["steps"][-1][pid]["observation"]["private"],
                "overage_first": replay["steps"][1][pid]["observation"][
                    "remainingOverageTime"
                ],
                "overage_final": replay["steps"][-1][pid]["observation"][
                    "remainingOverageTime"
                ],
            }
        )
        ps["daily_hires"] = [
            sum(o["op"] == "HIRE" and o["step"] // 24 == day for o in player_orders)
            for day in range(30)
        ]
        ps["daily_hire_cost"] = [
            sum(
                o["price"]
                for o in player_orders
                if o["op"] == "HIRE" and o["step"] // 24 == day
            )
            for day in range(30)
        ]
        ps["production"] = dict(collections.Counter())
        for u in player_units:
            if u["action"][0] in ("HARVEST", "COLLECT_FERTILIZER"):
                for item, qty in u["gains"].items():
                    ps["production"][item] = ps["production"].get(item, 0) + qty
        player_summaries.append(ps)

    result = {
        "episode_id": eid,
        "target_seat": target,
        "engine": replay["module_version"],
        "seed": replay["info"]["seed"],
        "source_sha256": hashlib.sha256(raw).hexdigest(),
        "verified_transitions": len(replay["steps"]) - 1,
        "players": player_summaries,
        "days": days,
    }
    (ROOT / f"analysis-{eid}.json").write_text(json.dumps(result, indent=2))
    with gzip.open(ROOT / f"events-{eid}.json.gz", "wt") as f:
        json.dump({"units": units, "orders": orders, "losses": losses}, f)
    # TSV permits independent inspection without running Python.
    if eid == 111105944:
        with (ROOT / "specified-game-actions.tsv").open("w") as f:
            writer = csv.writer(f, delimiter="\t")
            writer.writerow(
                [
                    "decision_step",
                    "day_zero_based",
                    "hour_zero_based",
                    "player",
                    "farmer",
                    "hands",
                    "market",
                ]
            )
            for t, step in enumerate(replay["steps"][1:]):
                for pid in (1, 0):
                    a = step[pid]["action"]
                    writer.writerow(
                        [
                            t,
                            t // 24,
                            t % 24,
                            replay["info"]["TeamNames"][pid],
                            json.dumps(a.get("farmer")),
                            json.dumps(a.get("hands")),
                            json.dumps(a.get("market")),
                        ]
                    )
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest",
        type=pathlib.Path,
        default=pathlib.Path(__file__).parent / "sample-manifest.json",
    )
    parser.add_argument("episodes", nargs="*", type=int)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    ids = set(args.episodes)
    for entry in manifest["episodes"]:
        if ids and entry["id"] not in ids:
            continue
        path = ROOT / f"analysis-{entry['id']}.json"
        if path.exists():
            print(entry["id"], "already audited", flush=True)
            continue
        result = audit(entry)
        p = result["players"][result["target_seat"]]
        print(
            entry["id"],
            "verified",
            result["verified_transitions"],
            "money",
            p["final_money"],
            "income",
            p["income"],
            "cost",
            p["cost"],
            flush=True,
        )


if __name__ == "__main__":
    main()
