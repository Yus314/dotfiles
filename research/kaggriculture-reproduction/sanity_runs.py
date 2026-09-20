"""Adaptive-opponent smoke games on seeds absent from the supplied replay set."""

import json
from threadpoolctl import threadpool_limits
from policy import ROOT
from evaluate import use_native, rollout, ART


def main():
    entry = json.loads((ROOT / "sample-manifest.json").read_text())["episodes"][0]
    use_native()
    results = []
    with threadpool_limits(limits=1):
        for seed, seat, opponent in [
            (314159, 0, "starter"),
            (271828, 1, "starter"),
            (20260920, 0, "self"),
        ]:
            result = rollout(entry, opponent, seed, seat)
            results.append(result)
            print(
                json.dumps(
                    {
                        k: result[k]
                        for k in ["seed", "target_seat", "mode", "money", "runtime_max"]
                    }
                ),
                flush=True,
            )
            (ART / "adaptive-new-seeds.json").write_text(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
