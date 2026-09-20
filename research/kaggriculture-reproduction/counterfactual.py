"""Fixed-action counterfactuals. These do not execute an adaptive opponent."""

import copy
from pathlib import Path
import gzip
import json
from audit_replays import ROOT, Node, node, load_engine

CASH_GOODS = {"CARROT", "TOMATO", "STRAWBERRY", "MELON", "EGG", "MILK", "WOOL"}


def run(replay, seat, mode, start=288):
    eng = load_engine()
    state = node(copy.deepcopy(replay["steps"][start]))
    env = Node(
        configuration=node(replay["configuration"]),
        info=node(replay["info"]),
        done=False,
    )
    divergences = [0, 0]
    delayed = []
    for t in range(start, len(replay["steps"]) - 1):
        for pid in range(2):
            state[pid].observation.step = t
            state[pid].action = node(
                copy.deepcopy(replay["steps"][t + 1][pid]["action"])
            )
        act = state[seat].action
        market = act.get("market", [])
        keep = [o for o in market if not (o[0] == "SELL" and o[1] in CASH_GOODS)]
        if mode == "immediate":
            shed = state[seat].observation.private.shed
            sales = [
                ["SELL", k, shed.get(k, 0)]
                for k in sorted(CASH_GOODS)
                if shed.get(k, 0)
            ]
            act["market"] = keep + sales
        elif mode == "delay_one_turn":
            now = [o for o in market if o[0] == "SELL" and o[1] in CASH_GOODS]
            if t == len(replay["steps"]) - 2:
                totals = {}
                for o in delayed + now:
                    totals[o[1]] = totals.get(o[1], 0) + o[2]
                act["market"] = keep + [["SELL", k, q] for k, q in totals.items()]
            else:
                act["market"] = keep + delayed
            delayed = now
        eng.interpreter(state, env)
        for pid in range(2):
            actual = state[0].observation.farms[pid]
            baseline = replay["steps"][t + 1][0]["observation"]["farms"][pid]
            if {k: v for k, v in actual.items() if k != "money"} != {
                k: v for k, v in baseline.items() if k != "money"
            }:
                divergences[pid] += 1
    money = [s.observation.farms[pid].money for pid, s in enumerate(state)]
    delta = [money[i] - replay["rewards"][i] for i in range(2)]
    return {
        "mode": mode,
        "start_decision": start,
        "money": money,
        "delta": delta,
        "target_delta": delta[seat],
        "margin_delta": delta[seat] - delta[1 - seat],
        "farm_state_divergent_steps": divergences,
    }


def main():
    entries = json.loads((Path(__file__).parent / "sample-manifest.json").read_text())[
        "episodes"
    ]
    output = []
    for entry in entries:
        eid = entry["id"]
        replay = json.loads(
            gzip.decompress((ROOT / f"episode-{eid}.json.gz").read_bytes())
        )
        analysis = json.loads((ROOT / f"analysis-{eid}.json").read_text())
        seat = analysis["target_seat"]
        for mode in ("immediate", "delay_one_turn"):
            r = run(replay, seat, mode)
            r.update(episode_id=eid, target_seat=seat)
            output.append(r)
            print(
                eid,
                mode,
                r["target_delta"],
                r["margin_delta"],
                r["farm_state_divergent_steps"],
                flush=True,
            )
    (ROOT / "counterfactual-results.json").write_text(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
