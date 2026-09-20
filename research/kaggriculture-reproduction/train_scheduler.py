"""Repair DIG feature labels and re-mine hard negatives on the original 50 games.

Only the task ranking head is retrained. No final-validation replay is opened.
"""

import os

os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
import concurrent.futures, gzip, importlib.util, json, pickle, shutil
from pathlib import Path
import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from threadpoolctl import threadpool_limits
from train import ART, ROOT, read_episode, next_task, unit_action, taskkey, export_model

DEST = ROOT / "baselines/v9-trained"
CACHE = ART / "scheduler-training"


def normalize_dig_rows(X, opcol, itemcol, dig_id):
    """Normalize all item-dependent columns, keeping destination-tile fields."""
    dig = X[:, opcol] == dig_id
    changed = dig & (X[:, itemcol] != 0)
    for col in (
        itemcol,
        X.shape[1] - 6,
        X.shape[1] - 5,
        X.shape[1] - 3,
        X.shape[1] - 2,
        X.shape[1] - 1,
    ):
        X[dig, col] = 0
    return dig, changed


def candidate():
    spec = importlib.util.spec_from_file_location(
        "candidate", ROOT / "baselines/v9-candidate/policy.py"
    )
    p = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(p)
    return p


def mine(entry):
    path = CACHE / f"{entry['id']}.npz"
    if path.exists():
        return str(path)
    p = candidate()
    with (ART / "native-models.pkl").open("rb") as f:
        rank = pickle.load(f)["rank"]
    r, seat = read_episode(entry)
    xs, ys = [], []
    with threadpool_limits(limits=1):
        for t in range(0, 719, 4):
            c = p.Context(r["steps"][t][seat]["observation"])
            batch, ranges = [], []
            for idx in range(len(c.positions)):
                task = next_task(r, t, seat, idx)
                a = unit_action(r, t, seat, idx)
                if task is None:
                    if a[0] != "PASS":
                        continue
                    task = ("PASS", "", *c.positions[idx], 1)
                neg = [z for z in c.candidates(idx) if taskkey(z) != taskkey(task)]
                lo = len(batch)
                batch.extend(c.features(idx, z) for z in neg)
                ranges.append((idx, task, lo, len(batch)))
            if not batch:
                continue
            X = np.asarray(batch, dtype=np.float32)
            scores = rank.decision_function(X)
            for idx, task, lo, hi in ranges:
                xs.append(c.features(idx, task))
                ys.append(1)
                for j in np.argsort(scores[lo:hi])[-5:] + lo:
                    xs.append(X[j])
                    ys.append(0)
    np.savez_compressed(
        path, x=np.asarray(xs, dtype=np.float32), y=np.asarray(ys, dtype=np.float32)
    )
    return str(path)


def main():
    CACHE.mkdir(exist_ok=True)
    DEST.mkdir(exist_ok=True)
    p = candidate()
    freeze = json.loads((ROOT / "baselines/v7/FREEZE.json").read_text())
    allowed = set(freeze["training_episodes"])
    entries = sum(
        (
            json.loads((ROOT / name).read_text())["episodes"]
            for name in ["sample-manifest.json", "additional-train-manifest.json"]
        ),
        [],
    )
    entries = [e for e in entries if e["id"] in allowed]
    assert len(entries) == 50 and {e["id"] for e in entries} == allowed
    paths = []
    with concurrent.futures.ProcessPoolExecutor(max_workers=4) as pool:
        for path in pool.map(mine, entries):
            paths.append(Path(path))
            print("mined", path, flush=True)
    r, s = read_episode(entries[0])
    context = p.Context(r["steps"][0][s]["observation"])
    opcol, itemcol = len(context.global_features), len(context.global_features) + 1
    with np.load(ART / "dataset.npz") as base:
        X, y = base["rank_x0"].copy(), base["rank_y0"].copy()
    dig, changed = normalize_dig_rows(X, opcol, itemcol, p.OP_ID["DIG"])
    positive = {row.tobytes() for row in X[dig & (y == 1)]}
    keep = np.ones(len(y), dtype=bool)
    for i in np.flatnonzero(changed & (y == 0)):
        if X[i].tobytes() in positive:
            keep[i] = False
    xs, ys = [X[keep]], [y[keep]]
    for path in paths:
        with np.load(path) as d:
            xs.append(d["x"])
            ys.append(d["y"])
    X, y = np.concatenate(xs), np.concatenate(ys)
    del xs, ys
    print(
        "fit",
        X.shape,
        "corrected_DIG_rows",
        int(changed.sum()),
        "removed_contradictions",
        int((~keep).sum()),
        flush=True,
    )
    model = HistGradientBoostingClassifier(
        max_iter=400,
        max_leaf_nodes=63,
        max_depth=10,
        min_samples_leaf=30,
        l2_regularization=2,
        learning_rate=0.075,
        early_stopping=False,
        random_state=712,
    )
    with threadpool_limits(limits=4):
        model.fit(X, y)
    with (ART / "native-models.pkl").open("rb") as f:
        heads = pickle.load(f)
    heads["rank"] = model
    with (CACHE / "native-models.pkl").open("wb") as f:
        pickle.dump(heads, f)
    for name in [
        "main.py",
        "policy.py",
        "engine.py",
        "kaggriculture.json",
        "NOTICE.md",
        "LICENSE.engine",
        "requirements.txt",
    ]:
        shutil.copy2(ROOT / "baselines/v9-candidate" / name, DEST / name)
    raw = json.loads(gzip.decompress((ROOT / "models.json.gz").read_bytes()))
    raw["rank"] = export_model(model)
    (DEST / "models.json.gz").write_bytes(
        gzip.compress(json.dumps(raw).encode(), mtime=0)
    )
    sample = X[np.linspace(0, len(X) - 1, 1000, dtype=int)]
    with threadpool_limits(limits=1):
        assert np.allclose(
            model.decision_function(sample),
            p.TreeModel(raw["rank"]).predict(sample),
            rtol=1e-10,
            atol=1e-10,
        )
    metrics = {
        "training_episodes": sorted(allowed),
        "training_rows": len(y),
        "corrected_DIG_rows": int(changed.sum()),
        "removed_contradictory_negative_rows": int((~keep).sum()),
        "changed_heads": ["rank"],
        "other_exported_heads_unchanged": True,
        "export_parity_1000_rows": True,
    }
    (CACHE / "training.json").write_text(json.dumps(metrics, indent=2) + "\n")
    print(json.dumps(metrics), flush=True)


if __name__ == "__main__":
    main()
