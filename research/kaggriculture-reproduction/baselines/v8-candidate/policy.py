"""Observation-only task and market policy. No replay/episode IDs at runtime."""

from __future__ import annotations
import copy
import gzip
import json
import math
from pathlib import Path
from collections import Counter
import numpy as np
import engine as E

ROOT = Path(__file__).parent
ITEMS = E.PRODUCTS + ["COW", "SHEEP", "GOOSE"]
ITEM_ID = {k: i + 1 for i, k in enumerate(ITEMS)}
CROPS = list(E.CROPS)
ANIMALS = list(E.ANIMALS)
SHOPS = sorted(E.SHOPS)
OPS = [
    "WATER",
    "HARVEST",
    "FEED",
    "CARE",
    "COLLECT_FERTILIZER",
    "FERTILIZE",
    "PLANT",
    "BUILD_PASTURE",
    "BUILD_COOP",
    "PLACE",
    "PICKUP",
    "DROP",
    "DIG",
    "PASS",
]
OP_ID = {k: i for i, k in enumerate(OPS)}
MOVES = E.FARMER_MOVES
ACCESS = [(4, 4), (5, 4), (4, 5), (5, 5)]
OPTIONS = {
    "deficit_weight": 0.0,
    "emergency_weight": 0.0,
    "goal_bonus": 0.0,
    "crop_mode": "hard",
    "crop_slack": 4,
    "crop_penalty": 2.0,
    "animal_purchase_cap": True,
}
_MEMORY = {}
_ANIMAL_MEMORY = {}
HIRE_SCHEDULE = [4, 4, 6, 5, 6, 6, 8, 9, 9, 10] + [11] * 18 + [10, 10]


def distance(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


def shed_distance(p):
    return min(distance(p, q) for q in ACCESS)


def observe_animal_purchases(obs):
    """Count observed acquisitions, without treating a lost animal as new demand.

    Placement and pickup merely move animals between containers. Only a rise in
    their combined count records a purchase. A discontinuous observation stream
    starts a fresh estimate; no assumed purchases are credited before execution.
    """
    seat = obs.get("player", 0)
    step = obs.get("step", obs.get("day", 0) * 24 + obs.get("hour", 0))
    farm, private = obs["farms"][seat], obs["private"]
    current = Counter(
        t.get("animal")
        for row in farm["tiles"]
        for t in row
        if isinstance(t, dict) and "animal" in t
    )
    for inv in [private["shed"]] + private["inventories"]:
        current.update({a: inv.get(a, 0) for a in ANIMALS})
    previous = _ANIMAL_MEMORY.get(seat)
    if step == 0 or previous is None or previous["step"] not in (step - 1, step):
        purchased = current.copy()
    elif previous["step"] == step:
        return previous["purchased"]
    else:
        purchased = previous["purchased"].copy()
        for a in ANIMALS:
            purchased[a] += max(0, current[a] - previous["current"][a])
    _ANIMAL_MEMORY[seat] = {"step": step, "current": current, "purchased": purchased}
    return purchased


class Context:
    def __init__(self, obs):
        self.obs = obs
        self.day = int(obs.get("day", obs.get("step", 0) // 24))
        self.hour = int(obs.get("hour", obs.get("step", 0) % 24))
        self.step = int(obs.get("step", self.day * 24 + self.hour))
        self.targets = None
        self.seat = obs.get("player", 0)
        self.farm = obs["farms"][self.seat]
        self.foe = obs["farms"][1 - self.seat]
        self.private = obs["private"]
        self.shed = self.private["shed"]
        self.seeds = self.private["seeds"]
        self.positions = [self.farm["farmer"]] + self.farm["hands"]
        self.invs = self.private["inventories"]
        self.tiles = self.farm["tiles"]
        self.prices = obs["market"]["prices"]
        self.money = self.farm["money"]
        self.count = Counter()
        self.foecount = Counter()
        self.yields = Counter()
        self.demand = Counter()
        self.shops = Counter(obs["town"]["unlocked_shops"])
        self.empty = []
        self.unfed = 0
        self.dry = 0
        for y, row in enumerate(self.tiles):
            for x, t in enumerate(row):
                if t is None:
                    self.empty.append((x, y))
                    continue
                if not isinstance(t, dict):
                    continue
                typ = t.get("crop", t.get("animal", t.get("kind")))
                self.count[typ] += 1
                if "crop" in t:
                    self.yields[t["crop"]] += t["yield_units"]
                    self.dry += not t["watered_today"]
                if "animal" in t:
                    self.yields[E.ANIMALS[t["animal"]]["product"]] += t["yield_units"]
                    self.unfed += not t["fed_today"]
        for row in self.foe["tiles"]:
            for t in row:
                if isinstance(t, dict):
                    self.foecount[t.get("crop", t.get("animal", t.get("kind")))] += 1
        for shop, n in self.shops.items():
            for item in E.SHOPS[shop]:
                self.demand[item] += n * (2 if len(E.SHOPS[shop]) == 1 else 1)
        self.totalanimals = sum(self.count[a] for a in ANIMALS)
        self.global_features = [
            self.day,
            self.hour,
            29 - self.day,
            self.money,
            math.log1p(max(0, self.money)),
            len(self.positions),
            len(self.farm["unlocked_quadrants"]),
            len(self.empty),
            self.count["WEED"],
            self.unfed,
            self.dry,
            sum(self.shed.values()),
        ]
        self.global_features += [self.count[i] for i in ITEMS] + [
            self.foecount[i] for i in ITEMS
        ]
        self.global_features += [self.prices[i] for i in E.PRODUCTS]
        self.global_features += [
            obs["market"]["inventory"][i] - 10000 for i in E.PRODUCTS
        ]
        self.global_features += [self.demand[i] for i in E.PRODUCTS] + [
            self.shops[s] for s in SHOPS
        ]
        self.global_features += [self.yields[i] for i in E.PRODUCTS] + [
            self.seeds.get(i, 0) for i in CROPS
        ]
        self.plan_features = (
            [self.day, self.hour]
            + [self.shops[k] for k in SHOPS]
            + [self.prices[i] for i in E.PRODUCTS]
            + [self.foecount[i] for i in ITEMS]
        )

    def carrying(self, idx):
        inv = self.invs[idx]
        return sum(inv.get(a, 0) for a in ANIMALS)

    def inventory_value(self, idx):
        return sum(self.prices.get(k, 0) * v for k, v in self.invs[idx].items())

    def features(self, idx, task):
        op, item, x, y, n = task
        px, py = self.positions[idx]
        inv = self.invs[idx]
        tile = self.tiles[y][x]
        tile = tile if isinstance(tile, dict) else {}
        typ = tile.get("crop", tile.get("animal", ""))
        age = self.day - tile.get("planted_day", tile.get("placed_day", self.day))
        local = [
            OP_ID[op],
            ITEM_ID.get(item, 0),
            x,
            y,
            px,
            py,
            x - px,
            y - py,
            abs(x - px),
            abs(y - py),
            distance((px, py), (x, y)),
            shed_distance((x, y)),
            shed_distance((px, py)),
            idx,
            sum(inv.values()),
            self.inventory_value(idx),
            self.carrying(idx),
            int((px, py) in ACCESS),
            int((x, y) in ACCESS),
        ]
        local += [inv.get(i, 0) for i in ITEMS]
        local += [
            ITEM_ID.get(typ, 0),
            age,
            tile.get("yield_units", 0),
            tile.get("watered_today", False),
            tile.get("fed_today", False),
            tile.get("cared_today", False),
            tile.get("fertilizer_available", False),
            tile.get("consecutive_unwatered", 0),
            tile.get("consecutive_unfed", 0),
            tile.get("fertilized_until_day", -1) - self.day,
            tile.get("pending_care_bonus", 0),
            tile.get("max_lifespan_step", -1) - self.step,
            self.seeds.get(item, 0),
            self.shed.get(item, 0),
            n,
            self.prices.get(item, 0),
            self.demand.get(item, 0),
            self.count.get(item, 0),
        ]
        return self.global_features + local

    def crop_allowed(self, crop, assigned=0):
        if self.targets is None:
            return True
        # Preserve the observed melon opening; other targets are uncertain forecasts.
        hard = crop == "MELON" or OPTIONS["crop_mode"] == "hard"
        if hard:
            return self.count[crop] + assigned < self.targets[crop]
        if OPTIONS["crop_mode"] == "slack":
            return (
                self.count[crop] + assigned < self.targets[crop] + OPTIONS["crop_slack"]
            )
        return True

    def crop_penalty(self, crop, assigned=0):
        if self.targets is None or crop == "MELON" or OPTIONS["crop_mode"] != "soft":
            return 0.0
        proposed = self.count[crop] + assigned + 1
        return OPTIONS["crop_penalty"] * max(
            0.0, math.log((proposed + 1) / (self.targets[crop] + 1))
        )

    def candidates(self, idx, strict=False):
        inv = self.invs[idx]
        p = self.positions[idx]
        tasks = []
        animal = next((a for a in ANIMALS if inv.get(a, 0) > 0), None)
        for y, row in enumerate(self.tiles):
            for x, t in enumerate(row):
                dist = distance(p, (x, y))
                # A final-day task must leave time for walking back and dropping.
                remaining = 23 - self.hour
                if dist > remaining:
                    continue
                if t == "LOCKED":
                    continue
                if t is None:
                    if animal and shed_distance((x, y)) <= 4:
                        tasks.append(
                            (
                                "BUILD_COOP" if animal == "GOOSE" else "BUILD_PASTURE",
                                "",
                                x,
                                y,
                                1,
                            )
                        )
                    if not animal and self.day <= 27 and self.hour <= 21:
                        for crop in CROPS:
                            if crop == "MELON" and (
                                self.day > 2 or self.count[crop] >= 12
                            ):
                                continue
                            if crop == "STRAWBERRY" and self.day < 2:
                                continue
                            if crop == "TOMATO" and self.day < 9:
                                continue
                            if not self.crop_allowed(crop):
                                continue
                            if self.day + E.CROPS[crop]["first_yield_day"] > 29:
                                continue
                            if (
                                self.seeds.get(crop, 0) <= 0
                                and self.money < E.CROPS[crop]["seed"]
                            ):
                                continue
                            tasks.append(("PLANT", crop, x, y, 1))
                    continue
                if not isinstance(t, dict):
                    continue
                crop = t.get("crop")
                ani = t.get("animal")
                if crop:
                    age = self.day - t["planted_day"]
                    if not t["watered_today"]:
                        tasks.append(("WATER", crop, x, y, 1))
                    if t["yield_units"] > 0 and age >= E.CROPS[crop]["first_yield_day"]:
                        if (
                            self.day != 29
                            or dist + shed_distance((x, y)) + 2 <= remaining
                        ):
                            tasks.append(("HARVEST", crop, x, y, 1))
                    if (
                        inv.get("FERTILIZER", 0) > 0
                        and t.get("fertilized_until_day", -1) < self.day + 2
                        and self.day < 29
                    ):
                        tasks.append(("FERTILIZE", crop, x, y, 1))
                    # Allow crop replacement, but never casually dig a new plant.
                    if (
                        age >= E.CROPS[crop]["first_yield_day"]
                        or t.get("max_lifespan_step", -1) > 0
                        and t["max_lifespan_step"] <= self.step
                    ):
                        tasks.append(("DIG", crop, x, y, 1))
                elif ani:
                    if not t["fed_today"] and inv.get("WHEAT", 0) > 0 and self.day < 29:
                        tasks.append(("FEED", ani, x, y, 1))
                    if not t["cared_today"] and self.day < 29:
                        tasks.append(("CARE", ani, x, y, 1))
                    if t["fertilizer_available"] and (
                        self.day != 29 or dist + shed_distance((x, y)) + 2 <= remaining
                    ):
                        tasks.append(("COLLECT_FERTILIZER", ani, x, y, 1))
                    if t["yield_units"] > 0 and (
                        self.day != 29 or dist + shed_distance((x, y)) + 2 <= remaining
                    ):
                        tasks.append(("HARVEST", ani, x, y, 1))
                elif t.get("kind") in ("PASTURE", "COOP"):
                    if animal and E.ANIMALS[animal]["structure"] == t["kind"]:
                        tasks.append(("PLACE", animal, x, y, 1))
                    elif not animal:
                        tasks.append(("DIG", "", x, y, 1))
                elif t.get("kind") == "WEED":
                    tasks.append(("DIG", "", x, y, 1))
        for x, y in ACCESS:
            if (
                self.shed.get("WHEAT", 0) > 0
                and inv.get("WHEAT", 0) == 0
                and self.unfed > 0
                and self.day < 29
            ):
                q = min(
                    self.shed["WHEAT"],
                    max(
                        1,
                        min(5, math.ceil(self.unfed / max(1, len(self.positions) / 3))),
                    ),
                )
                tasks.append(("PICKUP", "WHEAT", x, y, q))
            if not animal:
                for ani in ANIMALS:
                    if self.shed.get(ani, 0) > 0:
                        tasks.append(("PICKUP", ani, x, y, 1))
            if sum(inv.values()) > 0:
                tasks.append(("DROP", "", x, y, 1))
                # PLACE only selected products, preserving feed or fertilizer.
                for item, n in inv.items():
                    if n > 0 and item not in ANIMALS and item != "WHEAT":
                        tasks.append(("PLACE", item, x, y, n))
        tasks.append(("PASS", "", p[0], p[1], 1))
        return tasks


def project_units(obs, action):
    farm = copy.deepcopy(obs["farms"][obs.get("player", 0)])
    private = copy.deepcopy(obs["private"])
    actions = [action.get("farmer", ["PASS"])] + action.get("hands", [])
    requested = Counter(a[1] for a in actions if a[0] == "PLANT")
    blocked = {k for k, n in requested.items() if n > private["seeds"].get(k, 0)}
    for idx, a in enumerate(actions):
        if a[0] == "PLANT" and a[1] in blocked:
            continue
        E._apply_unit_action(farm, private, idx, a, 10, obs["day"], 24, 100)
    return farm, private


def sale_features(c, item, private):
    inv = private["shed"]
    q = inv.get(item, 0)
    carried = Counter()
    for unit in private["inventories"]:
        carried.update(unit)
    ownprod = next((a for a in ANIMALS if E.ANIMALS[a]["product"] == item), item)
    return (
        c.global_features
        + [
            ITEM_ID[item],
            q,
            sum(inv.values()),
            carried[item],
            sum(carried.values()),
            c.prices[item],
            c.obs["market"]["inventory"][item] - 10000,
            c.demand[item],
            c.yields[item],
            c.count[ownprod],
            c.foecount[ownprod],
            c.hour % 4,
            c.hour % 24,
            int(c.day == 29),
        ]
        + [inv.get(k, 0) for k in E.PRODUCTS]
        + [carried.get(k, 0) for k in E.PRODUCTS]
    )


class TreeModel:
    """Exported sklearn histogram trees, inference uses only NumPy."""

    def __init__(self, data):
        self.bias = data["bias"]
        self.trees = []
        for tree in data["trees"]:
            self.trees.append(
                {
                    k: np.asarray(
                        v,
                        dtype=(
                            np.int32
                            if k in ("left", "right", "feature", "leaf")
                            else np.float64
                        ),
                    )
                    for k, v in tree.items()
                }
            )

    def predict(self, X):
        X = np.asarray(X, dtype=np.float64)
        out = np.full(len(X), self.bias, dtype=float)
        rows = np.arange(len(X))
        for t in self.trees:
            idx = np.zeros(len(X), dtype=np.int32)
            while True:
                alive = t["leaf"][idx] == 0
                if not alive.any():
                    break
                r = rows[alive]
                n = idx[alive]
                idx[alive] = np.where(
                    X[r, t["feature"][n]] <= t["threshold"][n],
                    t["left"][n],
                    t["right"][n],
                )
            out += t["value"][idx]
        return out


_MODELS = None


def models():
    global _MODELS
    if _MODELS is None:
        with gzip.open(ROOT / "models.json.gz", "rt") as f:
            raw = json.load(f)
        _MODELS = {k: TreeModel(v) for k, v in raw.items()}
    return _MODELS


def task_action(c, idx, t):
    op, item, x, y, n = t
    px, py = c.positions[idx]
    if (px, py) != (x, y):
        horizontal = False
        if x != px and y != py and "axis" in models():
            horizontal = float(models()["axis"].predict([c.features(idx, t)])[0]) > 0
        if x != px and (horizontal or y == py):
            return ["WEST" if x < px else "EAST"]
        return ["NORTH" if y < py else "SOUTH"]
    if op in ("PLANT", "PLACE", "PICKUP"):
        if op == "PICKUP" and item == "WHEAT" and "pickup_wheat" in models():
            n = max(
                1,
                min(
                    c.shed.get(item, 1),
                    round(
                        float(
                            models()["pickup_wheat"].predict(
                                [c.features(idx, ("PICKUP", "WHEAT", x, y, 1))]
                            )[0]
                        )
                    ),
                ),
            )
        return [op, item, n] if op != "PLANT" else [op, item]
    return [op]


def choose_units(c, model):
    all_tasks = []
    features = []
    ranges = []
    for idx in range(len(c.positions)):
        tasks = c.candidates(idx)
        ranges.append((len(all_tasks), len(all_tasks) + len(tasks)))
        all_tasks.extend(tasks)
        features.extend(c.features(idx, t) for t in tasks)
    scores = model.predict(features)
    chosen = []
    reserved = set()
    seed_used = Counter()
    pickup_used = Counter()
    plant_jobs = Counter()
    previous = _MEMORY.get(c.seat, {})
    previous_tasks = (
        previous.get("tasks", [])
        if previous.get("step") == c.step - 1 and c.hour > 0
        else []
    )
    # Process urgent current-tile work first, then globally strongest assignments.
    pending = set(range(len(c.positions)))
    assigned = {}
    while pending:
        best = None
        for idx in pending:
            lo, hi = ranges[idx]
            for j in range(lo, hi):
                op, item, x, y, n = all_tasks[j]
                key = (
                    (op, x, y)
                    if op not in ("PICKUP", "DROP", "PLACE", "PASS")
                    else None
                )
                if key is not None and key in reserved:
                    continue
                if op == "PICKUP" and c.shed.get(item, 0) - pickup_used[item] <= 0:
                    continue
                if (
                    op == "PLANT"
                    and (x, y) == tuple(c.positions[idx])
                    and c.seeds.get(item, 0) - seed_used[item] <= 0
                ):
                    continue
                if op == "PLANT" and not c.crop_allowed(item, plant_jobs[item]):
                    continue
                score = scores[j]
                if op == "PLANT":
                    score -= c.crop_penalty(item, plant_jobs[item])
                if op == "PLANT" and c.targets is not None:
                    score += OPTIONS["deficit_weight"] * math.log(
                        (c.targets[item] + 1) / (c.count[item] + plant_jobs[item] + 1)
                    )
                tile = c.tiles[y][x]
                if isinstance(tile, dict) and c.day < 29:
                    urgent = (
                        op == "FEED"
                        and tile.get("consecutive_unfed", 0) >= 1
                        and (
                            c.day < 16
                            or c.prices.get(
                                E.ANIMALS.get(item, {}).get("product", ""), 0
                            )
                            > c.prices["WHEAT"]
                        )
                    ) or (op == "WATER" and tile.get("consecutive_unwatered", 0) >= 1)
                    if urgent:
                        score += OPTIONS["emergency_weight"] * max(
                            0, (c.hour + distance(c.positions[idx], (x, y)) - 14) / 9
                        )
                if (
                    idx < len(previous_tasks)
                    and previous_tasks[idx] is not None
                    and tuple(previous_tasks[idx][:4]) == tuple(all_tasks[j][:4])
                ):
                    score += OPTIONS["goal_bonus"]
                # Final return is a hard feasibility constraint, not a replay lookup.
                if (
                    c.day == 29
                    and sum(c.invs[idx].values()) > 0
                    and 22 - c.hour <= shed_distance(c.positions[idx])
                ):
                    if op != "DROP":
                        continue
                    score += 20
                if best is None or score > best[0]:
                    best = (score, idx, j, key)
        if best is None:
            for idx in pending:
                assigned[idx] = ("PASS", "", *c.positions[idx], 1)
            break
        _, idx, j, key = best
        t = all_tasks[j]
        assigned[idx] = t
        pending.remove(idx)
        if key is not None:
            reserved.add(key)
        if t[0] == "PLANT" and tuple(c.positions[idx]) == (t[2], t[3]):
            seed_used[t[1]] += 1
        if t[0] == "PICKUP":
            pickup_used[t[1]] += t[4]
        if t[0] == "PLANT":
            plant_jobs[t[1]] += 1
    chosen = [assigned[i] for i in range(len(c.positions))]
    actions = [task_action(c, i, t) for i, t in enumerate(chosen)]
    _MEMORY[c.seat] = {
        "step": c.step,
        "tasks": [t if a[0] in MOVES else None for t, a in zip(chosen, actions)],
    }
    return chosen, actions


def market_orders(c, units, tasks, heads):
    action = {"farmer": units[0], "hands": units[1:]}
    farm, private = project_units(c.obs, action)
    items = [i for i in E.PRODUCTS if private["shed"].get(i, 0) > 0]
    sales = []
    if items:
        sale_head = "sale_quantity" if "sale_quantity" in heads else "sale"
        values = heads[sale_head].predict([sale_features(c, i, private) for i in items])
        for item, value in zip(items, values):
            q = private["shed"][item]
            n = max(
                0,
                min(
                    q, round(float(value) * (1 if sale_head == "sale_quantity" else q))
                ),
            )
            if c.day == 29 and c.hour >= 21:
                n = q
            if n:
                sales.append(["SELL", item, n])
    # Preserve the model's ranking by immediate revenue for scarce order slots.
    sales.sort(key=lambda o: o[2] * c.prices[o[1]], reverse=True)
    cash = c.money + sum(
        sum(
            E.market_price(o[1], c.obs["market"]["inventory"][o[1]] + j)
            for j in range(o[2])
        )
        for o in sales
    )
    buys = []
    target_hires = HIRE_SCHEDULE[min(c.day, 29)]
    for nth in range(c.farm["hires_today"], target_hires):
        cost = E._hire_cost(nth)
        if c.hour > 6 or cash < cost:
            break
        buys.append(["HIRE"])
        cash -= cost
    target_land = 1 + (c.day >= 6) + (c.day >= 9)
    if len(farm["unlocked_quadrants"]) < target_land and (c.day > 6 or c.hour >= 5):
        cost = E.LAND_PRICES[len(farm["unlocked_quadrants"]) - 1]
        if cash >= cost:
            buys.append(["BUY_LAND"])
            cash -= cost
    if c.day < 6:
        targets = {"COW": 2, "SHEEP": 3, "GOOSE": 0}
    else:
        targets = {
            a: max(0, round(float(heads["animal_" + a].predict([c.plan_features])[0])))
            for a in ANIMALS
        }
    present = Counter(
        t.get("animal") for row in farm["tiles"] for t in row if isinstance(t, dict)
    )
    if targets.get("GOOSE", 0) < 2 or c.shops["YARN_STORE"] > 0:
        targets["GOOSE"] = 0
    held = Counter(private["shed"])
    for inv in private["inventories"]:
        held.update(inv)
    for animal in ["COW", "SHEEP", "GOOSE"]:
        need = max(0, targets[animal] - present[animal] - held[animal])
        if OPTIONS["animal_purchase_cap"]:
            acquired = _ANIMAL_MEMORY[c.seat]["purchased"][animal]
            need = min(need, max(0, targets[animal] - acquired))
        n = min(need, int(cash // E.ANIMALS[animal]["cost"]))
        if n > 0 and c.day <= 15:
            buys.append(["BUY_ANIMAL", animal, n])
            cash -= n * E.ANIMALS[animal]["cost"]
    # Replenish food for the current day's remaining care work.
    feed = private["shed"].get("WHEAT", 0) + sum(
        v.get("WHEAT", 0) for v in private["inventories"]
    )
    need = max(0, c.unfed - feed) if c.day < 29 and c.hour < 16 else 0
    if need:
        n = min(need, int(cash // max(1, c.prices["WHEAT"] + 2)))
        if n > 0:
            buys.append(["BUY_PRODUCT", "WHEAT", n])
            cash -= n * (c.prices["WHEAT"] + 2)
    wanted = Counter()
    for idx, t in enumerate(tasks):
        if t[0] == "PLANT" and distance(c.positions[idx], (t[2], t[3])) <= 3:
            wanted[t[1]] += 1
    # Bootstrap a few seeds so that the planner can populate an empty farm.
    if c.day < 3:
        limit = [6, 10, 12][c.day]
        wanted["MELON"] = min(max(wanted["MELON"], 2), max(0, limit - c.count["MELON"]))
    for crop, n in wanted.items():
        n = max(0, n - private["seeds"].get(crop, 0))
        n = min(n, int(cash // E.CROPS[crop]["seed"]))
        if n:
            buys.append(["BUY_SEED", crop, n])
            cash -= n * E.CROPS[crop]["seed"]
    # Daily room must be made before inventories are auto-deposited.
    if c.hour >= 21:
        total = sum(private["shed"].values()) + sum(
            sum(i.values()) for i in private["inventories"]
        )
        existing = {o[1]: o[2] for o in sales}
        overflow = total - 100 - sum(existing.values())
        if overflow > 0:
            for item in sorted(items, key=lambda i: c.prices[i]):
                extra = min(
                    max(0, private["shed"][item] - existing.get(item, 0)), overflow
                )
                if extra:
                    if item in existing:
                        next(o for o in sales if o[1] == item)[2] += extra
                    else:
                        sales.append(["SELL", item, extra])
                    overflow -= extra
                if overflow <= 0:
                    break
    return (sales + buys)[:10]


def agent(obs, configuration=None):
    step = obs.get("step", obs.get("day", 0) * 24 + obs.get("hour", 0))
    if OPTIONS["animal_purchase_cap"]:
        observe_animal_purchases(obs)
    if step == 0:
        _MEMORY.pop(obs.get("player", 0), None)
    if step == 0:
        return {
            "farmer": ["PASS"],
            "hands": [],
            "market": [["BUY_ANIMAL", "COW", 1], ["BUY_PRODUCT", "WHEAT", 5]],
        }
    if step == 1:
        return {
            "farmer": ["PICKUP", "COW", 1],
            "hands": [],
            "market": [
                ["SELL", "WHEAT", 1],
                ["HIRE"],
                ["HIRE"],
                ["HIRE"],
                ["HIRE"],
                ["BUY_ANIMAL", "COW", 1],
                ["BUY_ANIMAL", "SHEEP", 3],
            ],
        }
    c = Context(obs)
    heads = models()
    c.targets = {
        crop: max(0, round(float(heads["crop_" + crop].predict([c.plan_features])[0])))
        for crop in CROPS
    }
    if c.day <= 2:
        c.targets["MELON"] = [6, 10, 12][c.day]
    if c.day == 0:
        c.targets["WHEAT"] = 10
    tasks, units = choose_units(c, heads["rank"])
    return {
        "farmer": units[0],
        "hands": units[1:],
        "market": market_orders(c, units, tasks, heads),
    }
