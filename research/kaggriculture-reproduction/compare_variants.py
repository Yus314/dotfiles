"""Paired experiments on explicit manifests; isolated policy state per job."""

import os

os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
import argparse, concurrent.futures, contextlib, hashlib, importlib.util, json
from pathlib import Path
from threadpoolctl import threadpool_limits
import policy
import evaluate
from evaluate import use_native, rollout, teacher
from train import HOLDOUT, ART

BASE_OPTIONS = dict(policy.OPTIONS)

VARIANTS = {
    "v7": {"_snapshot": "baselines/v7"},
    "v8": {"_snapshot": "baselines/v8-candidate"},
}


def worker(payload):
    entry, name, options, settings = payload
    phase, stride = settings["phase"], settings["stride"]
    directory = ART / "improvement" / phase
    directory.mkdir(parents=True, exist_ok=True)
    options = dict(options)
    snapshot = options.pop("_snapshot", None)
    native_path = options.pop("_native_models", None)
    chosen = policy
    if snapshot:
        spec = importlib.util.spec_from_file_location(
            "snapshot_policy", policy.ROOT / snapshot / "policy.py"
        )
        chosen = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(chosen)
    else:
        chosen.OPTIONS.clear()
        chosen.OPTIONS.update(BASE_OPTIONS)
    chosen.OPTIONS.update(options)
    chosen._MEMORY.clear()
    if hasattr(chosen, "_ANIMAL_MEMORY"):
        chosen._ANIMAL_MEMORY.clear()
    chosen._MODELS = None
    evaluate.policy = chosen
    if not settings["exported"]:
        use_native(policy.ROOT / native_path if native_path else None)
    with (
        (directory / f"{name}-{entry['id']}.log").open("w") as log,
        contextlib.redirect_stdout(log),
        threadpool_limits(limits=1),
    ):
        game = rollout(
            entry,
            town_mode=settings["town"],
            opponent=settings["opponent"],
            seed=settings["seed"],
            seat_override=settings["seat"],
        )
        agreement = (
            None
            if settings["skip_teacher"]
            else teacher(entry, stride, settings["task_metrics"])
        )
    result = {
        "variant": name,
        "options": dict(chosen.OPTIONS),
        "snapshot": snapshot,
        "policy_sha256": hashlib.sha256(Path(chosen.__file__).read_bytes()).hexdigest(),
        "models_sha256": hashlib.sha256(
            (chosen.ROOT / "models.json.gz").read_bytes()
        ).hexdigest(),
        "native_models": native_path,
        "exported": settings["exported"],
        "rollout": game,
        "teacher": agreement,
    }
    (directory / f"{name}-{entry['id']}.json").write_text(json.dumps(result, indent=2))
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase", default="crop")
    parser.add_argument("--variants", type=Path)
    parser.add_argument("--episodes", nargs="*", type=int)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--stride", type=int, default=3)
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument(
        "--town", choices=["recorded", "endogenous"], default="recorded"
    )
    parser.add_argument("--opponent", default="trace")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--seat", type=int)
    parser.add_argument("--exported", action="store_true")
    parser.add_argument("--skip-teacher", action="store_true")
    parser.add_argument("--task-metrics", action="store_true")
    args = parser.parse_args()
    variants = json.loads(args.variants.read_text()) if args.variants else VARIANTS
    entries = [
        e
        for e in json.loads(
            (args.manifest or policy.ROOT / "sample-manifest.json").read_text()
        )["episodes"]
        if (args.manifest is not None and not args.episodes)
        or e["id"] in (args.episodes or HOLDOUT)
    ]
    directory = ART / "improvement" / args.phase
    directory.mkdir(parents=True, exist_ok=True)
    jobs = [
        (e, name, options, vars(args))
        for e in entries
        for name, options in variants.items()
    ]
    results = []
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(worker, job) for job in jobs]
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            results.append(result)
            g = result["rollout"]
            t = result["teacher"]
            print(
                json.dumps(
                    {
                        "variant": result["variant"],
                        "episode": g["episode"],
                        "money": g["target_money"],
                        "unit": t["rate"]["unit"] if t else None,
                        "plant": t["by_operation"].get("PLANT") if t else None,
                        "losses": g["diagnostics"]["losses"],
                        "tasks": t.get("task_agreement") if t else None,
                    }
                ),
                flush=True,
            )
            (directory / "results.json").write_text(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
