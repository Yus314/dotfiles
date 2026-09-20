"""Teacher-forced agreement and closed-loop play, with explicit opponent mode."""

import os

os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
import argparse, collections, copy, hashlib, json, pickle, time
from pathlib import Path
import numpy as np
from threadpoolctl import threadpool_limits
import engine as E
import policy
from diagnostics import Audit
from train import HOLDOUT, ART, read_episode, next_task


class Node(dict):
    def __getattr__(self, k):
        try:
            return self[k]
        except KeyError as e:
            raise AttributeError(k) from e

    def __setattr__(self, k, v):
        self[k] = v


def node(v):
    if isinstance(v, dict):
        return Node({k: node(x) for k, x in v.items()})
    if isinstance(v, list):
        return [node(x) for x in v]
    return v


class Native:
    def __init__(self, model, rank=False):
        self.model = model
        self.rank = rank

    def predict(self, X):
        return (
            self.model.decision_function(np.asarray(X))
            if self.rank
            else self.model.predict(np.asarray(X))
        )


def use_native(path=None):
    with (Path(path) if path else ART / "native-models.pkl").open("rb") as f:
        heads = pickle.load(f)
    policy._MODELS = {k: Native(v, k in ("rank", "axis")) for k, v in heads.items()}


def teacher(entry, stride=12, task_metrics=False):
    r, s = read_episode(entry)
    correct = collections.Counter()
    total = collections.Counter()
    times = []
    confusion = collections.Counter()
    by_op = collections.Counter()
    correct_op = collections.Counter()
    goals = collections.Counter()
    for t in range(0 if stride == 1 else 2, 719, stride):
        obs = copy.deepcopy(r["steps"][t][s]["observation"])
        original = copy.deepcopy(obs)
        start = time.perf_counter()
        got = policy.agent(obs)
        times.append(time.perf_counter() - start)
        assert obs == original, "Agent mutated its observation"
        want = r["steps"][t + 1][s]["action"]
        ga = [got["farmer"]] + got["hands"]
        wa = [want["farmer"]] + want["hands"]
        assert len(ga) == len(wa), "Worker counts differ"
        if task_metrics:
            c = policy.Context(obs)
            memory = policy._MEMORY.get(c.seat, {}).get("tasks", [])
            for idx, action in enumerate(ga):
                reference = next_task(r, t, s, idx)
                if reference is None:
                    continue
                op = action[0]
                if op in E.FARMER_MOVES:
                    predicted = memory[idx] if idx < len(memory) else None
                else:
                    x, y = c.positions[idx]
                    tile = c.tiles[y][x]
                    tile = tile if isinstance(tile, dict) else {}
                    item = (
                        action[1]
                        if op in ("PLANT", "PICKUP", "PLACE")
                        else tile.get("crop", tile.get("animal", ""))
                    )
                    if op in ("DROP", "BUILD_PASTURE", "BUILD_COOP", "DIG", "PASS"):
                        item = ""
                    predicted = (op, item, x, y)
                if predicted and predicted[0] == "DIG":
                    predicted = ("DIG", "", *predicted[2:])
                goals["total"] += 1
                goals["exact"] += (
                    predicted is not None and tuple(predicted[:4]) == reference[:4]
                )
                goals["destination"] += (
                    predicted is not None and tuple(predicted[2:4]) == reference[2:4]
                )
                goals["operation"] += (
                    predicted is not None and predicted[0] == reference[0]
                )
        for a, b in zip(ga, wa):
            total["unit"] += 1
            correct["unit"] += a == b
            confusion[b[0] + ">" + a[0]] += 1
            by_op[b[0]] += 1
            correct_op[b[0]] += a == b
            total["op"] += 1
            correct["op"] += a[0] == b[0]
            if b[0] not in E.FARMER_MOVES:
                total["nonmovement"] += 1
                correct["nonmovement"] += a == b
        total["market_exact"] += 1
        correct["market_exact"] += got["market"] == want["market"]
    return {
        "episode": entry["id"],
        "mode": "teacher_forced",
        "stride": stride,
        "correct": dict(correct),
        "total": dict(total),
        "rate": {k: correct[k] / n for k, n in total.items()},
        "decisions": len(times),
        "by_operation": {
            k: {"total": v, "correct": correct_op[k]} for k, v in by_op.items()
        },
        "confusion": dict(confusion),
        "seconds_mean": float(np.mean(times)),
        "seconds_max": max(times),
        "task_agreement": dict(goals) if task_metrics else None,
    }


def rollout(
    entry, opponent="trace", seed=None, seat_override=None, town_mode="endogenous"
):
    r, s = read_episode(entry)
    if seat_override is not None:
        s = seat_override
    state = node(copy.deepcopy(r["steps"][0]))
    env = Node(configuration=node(r["configuration"]), info=node(r["info"]), done=False)
    if seed is not None:
        env.info["seed"] = seed
    times = []
    days = []
    actcounts = collections.Counter()
    action_digest = hashlib.sha256()
    audit = Audit(state[0].observation.farms[s], state[s].observation.private)
    for t in range(719):
        for i in range(2):
            state[i].observation.step = t
        start = time.perf_counter()
        act = policy.agent(state[s].observation)
        times.append(time.perf_counter() - start)
        action_digest.update(
            json.dumps(act, sort_keys=True, separators=(",", ":")).encode()
        )
        state[s].action = node(act)
        if opponent == "trace":
            state[1 - s].action = node(
                copy.deepcopy(r["steps"][t + 1][1 - s]["action"])
            )
        elif opponent == "starter":
            state[1 - s].action = node(E.starter_agent(state[1 - s].observation))
        elif opponent == "self":
            state[1 - s].action = node(policy.agent(state[1 - s].observation))
        elif opponent == "pass":
            state[1 - s].action = {"farmer": ["PASS"], "hands": [], "market": []}
        else:
            raise ValueError(opponent)
        for a in [act["farmer"]] + act["hands"]:
            actcounts[a[0]] += 1
        E.interpreter(state, env)
        if town_mode == "recorded":
            state[0].observation.town.unlocked_shops = copy.deepcopy(
                r["steps"][t + 1][0]["observation"]["town"]["unlocked_shops"]
            )
        if (t + 1) % 24 == 0 or t == 718:
            f = state[s].observation.farms[s]
            counts = collections.Counter(
                z.get("crop", z.get("animal", z.get("kind")))
                for row in f["tiles"]
                for z in row
                if isinstance(z, dict)
            )
            days.append(
                {
                    "day": t // 24,
                    "cash": f.money,
                    "counts": dict(counts),
                    "land": len(f.unlocked_quadrants),
                    "shops": list(state[s].observation.town.unlocked_shops),
                    "prices": dict(state[s].observation.market.prices),
                    "shed": dict(state[s].observation.private.shed),
                }
            )
            print(
                "day", t // 24, "cash", round(f.money), "farm", dict(counts), flush=True
            )
    money = [f.money for f in state[0].observation.farms]
    comparable = seed is None and seat_override is None and opponent == "trace"
    measured = audit.close()
    assert audit.farm["money"] == money[s]
    return {
        "episode": entry["id"],
        "seed": env.info["seed"],
        "target_seat": s,
        "mode": "closed_loop_vs_" + opponent,
        "town_mode": town_mode,
        "money": money,
        "target_money": money[s],
        "reference_target_money": r["rewards"][s] if comparable else None,
        "fraction_of_reference": money[s] / r["rewards"][s] if comparable else None,
        "action_sha256": action_digest.hexdigest(),
        "margin": money[s] - money[1 - s],
        "runtime_mean": float(np.mean(times)),
        "runtime_p95": float(np.quantile(times, 0.95)),
        "runtime_max": max(times),
        "actions": dict(actcounts),
        "days": days,
        "final_private": state[s].observation.private,
        "diagnostics": measured,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--episodes", nargs="*", type=int)
    parser.add_argument(
        "--manifest", type=Path, default=policy.ROOT / "sample-manifest.json"
    )
    parser.add_argument("--teacher", action="store_true")
    parser.add_argument("--stride", type=int, default=12)
    parser.add_argument("--opponent", default="trace")
    parser.add_argument("--exported", action="store_true")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--seat", type=int)
    parser.add_argument("--options")
    parser.add_argument(
        "--town", choices=["endogenous", "recorded"], default="endogenous"
    )
    parser.add_argument("--output", default="evaluation.json")
    args = parser.parse_args()
    if args.options:
        policy.OPTIONS.update(json.loads(args.options))
    entries = json.loads(args.manifest.read_text())["episodes"]
    ids = set(
        args.episodes
        or (
            [e["id"] for e in entries]
            if args.manifest.name != "sample-manifest.json"
            else HOLDOUT
        )
    )
    if not args.exported:
        use_native()
    missing = ids - {e["id"] for e in entries}
    if missing:
        raise ValueError(f"Episodes missing from manifest: {sorted(missing)}")
    out = []
    with threadpool_limits(limits=1):
        for entry in entries:
            if entry["id"] not in ids:
                continue
            z = (
                teacher(entry, args.stride)
                if args.teacher
                else rollout(entry, args.opponent, args.seed, args.seat, args.town)
            )
            out.append(z)
            print(
                json.dumps(
                    {
                        k: v
                        for k, v in z.items()
                        if k not in ["days", "final_private", "diagnostics"]
                    },
                    ensure_ascii=False,
                ),
                flush=True,
            )
            (ART / args.output).write_text(
                json.dumps(out, ensure_ascii=False, indent=2)
            )


if __name__ == "__main__":
    main()
