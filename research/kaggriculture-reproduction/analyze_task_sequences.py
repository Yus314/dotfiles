"""Diagnose destination errors and short closed-loop departures from expert states.

Future replay actions are evaluation labels only, never agent inputs.
"""

import os

os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
import argparse, collections, concurrent.futures, copy, json
from pathlib import Path
from threadpoolctl import threadpool_limits
import policy
from evaluate import use_native, node, Node
from diagnostics import Audit
from train import read_episode, next_task, unit_action, HOLDOUT, ART

OUT = ART / "sequence-diagnosis"
MOVES = policy.E.FARMER_MOVES
INVERSE = {"NORTH": "SOUTH", "SOUTH": "NORTH", "WEST": "EAST", "EAST": "WEST"}


class Capture:
    def __init__(self):
        self.original = policy.choose_units
        self.c = self.tasks = self.actions = None

    def choose(self, c, model):
        class Scores:
            def predict(inner, features):
                self.scores = model.predict(features)
                return self.scores

        self.c = c
        self.tasks, self.actions = self.original(c, Scores())
        return self.tasks, self.actions


def teacher_diagnosis(r, seat, capture, stride):
    counts = collections.Counter()
    by_op = collections.defaultdict(collections.Counter)
    examples = []
    for t in range(2, 719, stride):
        policy.agent(r["steps"][t][seat]["observation"])
        c = capture.c
        start = 0
        for idx, task in enumerate(capture.tasks):
            candidates = c.candidates(idx)
            scores = capture.scores[start : start + len(candidates)]
            start += len(candidates)
            want = next_task(r, t, seat, idx)
            act = unit_action(r, t, seat, idx)
            if want is None:
                continue
            counts["labelled_tasks"] += 1
            key = want[:4]
            same = task[:4] == key
            available = any(z[:4] == key for z in candidates)
            best = candidates[int(scores.argmax())]
            counts["task_exact"] += same
            counts["expert_candidate_available"] += available
            counts["independent_best_exact"] += best[:4] == key
            counts["coordination_helped"] += best[:4] != key and same
            counts["coordination_hurt"] += best[:4] == key and not same
            by_op[want[0]]["total"] += 1
            by_op[want[0]]["same"] += same
            by_op[want[0]]["missing"] += not available
            if act[0] in MOVES:
                counts["reference_moves"] += 1
                got = capture.actions[idx]
                counts["move_action_wrong"] += got != act
                if got != act:
                    counts["wrong_move_same_task"] += same
                    counts["wrong_move_different_task"] += not same
                    counts["wrong_move_different_operation"] += task[0] != want[0]
                    counts["wrong_move_different_destination"] += task[2:4] != want[2:4]
            if best[:4] == key and not same and len(examples) < 15:
                examples.append(
                    {
                        "step": t,
                        "worker": idx,
                        "position": c.positions[idx],
                        "wanted": want,
                        "chosen": task,
                        "best": best,
                    }
                )
    return {
        "stride": stride,
        "counts": dict(counts),
        "by_operation": dict(by_op),
        "examples": examples,
    }


def warm_rollout(r, seat, start, capture, expert=False):
    state = node(copy.deepcopy(r["steps"][start]))
    env = Node(configuration=node(r["configuration"]), info=node(r["info"]), done=False)
    audit = Audit(state[0].observation.farms[seat], state[seat].observation.private)
    policy._MEMORY.clear()
    previous = None
    metrics = collections.Counter()
    examples = []
    daily = []
    for t in range(start, min(start + 72, 719)):
        for s in range(2):
            state[s].observation.step = t
        if expert:
            action = copy.deepcopy(r["steps"][t + 1][seat]["action"])
        else:
            action = policy.agent(state[seat].observation)
            c = capture.c
            if previous is not None and c.hour > 0:
                for idx, (old, oldact) in enumerate(
                    zip(previous["tasks"], previous["actions"])
                ):
                    if idx >= len(capture.tasks) or oldact[0] not in MOVES:
                        continue
                    metrics["following_move"] += 1
                    current = capture.tasks[idx]
                    if old[:4] != current[:4]:
                        metrics["changed_task_after_move"] += 1
                        if any(z[:4] == old[:4] for z in c.candidates(idx)):
                            metrics["abandoned_still_available_task"] += 1
                            if tuple(c.positions[idx]) == tuple(old[2:4]):
                                metrics["arrived_but_changed_task"] += 1
                                if capture.actions[idx][0] in MOVES:
                                    metrics["arrived_then_walked_away"] += 1
                    if capture.actions[idx][0] == INVERSE[oldact[0]]:
                        metrics["immediate_backtrack"] += 1
                        if len(examples) < 15:
                            examples.append(
                                {
                                    "step": t,
                                    "worker": idx,
                                    "position": c.positions[idx],
                                    "old": old,
                                    "new": current,
                                }
                            )
            previous = {"tasks": capture.tasks, "actions": capture.actions}
        state[seat].action = node(action)
        state[1 - seat].action = node(
            copy.deepcopy(r["steps"][t + 1][1 - seat]["action"])
        )
        policy.E.interpreter(state, env)
        state[0].observation.town.unlocked_shops = copy.deepcopy(
            r["steps"][t + 1][0]["observation"]["town"]["unlocked_shops"]
        )
        if (t + 1) % 24 == 0:
            if expert:
                for s in range(2):
                    for field in ("farms", "private", "market", "town", "day", "hour"):
                        assert (
                            state[s].observation[field]
                            == r["steps"][t + 1][s]["observation"][field]
                        )
            daily.append(
                {
                    "day": t // 24,
                    "money": state[0].observation.farms[seat]["money"],
                    "shed": dict(state[seat].observation.private.shed),
                    "production": dict(audit.production),
                }
            )
    measured = audit.close()
    return {
        "start": start,
        "expert": expert,
        "money": state[0].observation.farms[seat]["money"],
        "metrics": dict(metrics),
        "examples": examples,
        "diagnostics": measured,
        "daily": daily,
    }


def worker(payload):
    entry, stride, warm = payload
    use_native()
    capture = Capture()
    policy.choose_units = capture.choose
    r, seat = read_episode(entry)
    with threadpool_limits(limits=1):
        result = {
            "episode": entry["id"],
            "teacher": teacher_diagnosis(r, seat, capture, stride),
        }
        if warm:
            result["warm"] = [
                warm_rollout(r, seat, day * 24, capture, expert)
                for day in [6, 12, 18]
                for expert in [True, False]
            ]
    policy.choose_units = capture.original
    OUT.mkdir(exist_ok=True)
    (OUT / f"{entry['id']}.json").write_text(json.dumps(result, indent=2))
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--stride", type=int, default=3)
    parser.add_argument("--warm", action="store_true")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()
    entries = json.loads(
        (args.manifest or policy.ROOT / "sample-manifest.json").read_text()
    )["episodes"]
    if args.manifest is None:
        entries = [e for e in entries if e["id"] in HOLDOUT]
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
        for result in pool.map(worker, [(e, args.stride, args.warm) for e in entries]):
            print(
                json.dumps(
                    {
                        "episode": result["episode"],
                        "teacher": result["teacher"]["counts"],
                        "warm": [
                            {
                                "start": x["start"],
                                "expert": x["expert"],
                                "money": x["money"],
                                **x["metrics"],
                            }
                            for x in result.get("warm", [])
                        ],
                    }
                ),
                flush=True,
            )


if __name__ == "__main__":
    main()
