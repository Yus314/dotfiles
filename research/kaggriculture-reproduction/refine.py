"""Mine competitive task alternatives and learn movement and pickup amounts."""

import os

os.environ.setdefault("OMP_NUM_THREADS", "4")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
import argparse, gzip, json, pickle, time
import numpy as np
from sklearn.ensemble import (
    HistGradientBoostingClassifier,
    HistGradientBoostingRegressor,
)
from sklearn.metrics import roc_auc_score, accuracy_score, mean_absolute_error
from threadpoolctl import threadpool_limits
from train import (
    HOLDOUT,
    ART,
    read_episode,
    next_task,
    taskkey,
    export_model,
    unit_action,
)
from policy import ROOT, Context, E, TreeModel


def build(heads, initial=False):
    hard_x = []
    hard_y = []
    axis_x = [[], []]
    axis_y = [[], []]
    qty_x = [[], []]
    qty_y = [[], []]
    entries = []
    for name in (
        ["sample-manifest.json"]
        if initial
        else ["sample-manifest.json", "additional-train-manifest.json"]
    ):
        entries += json.loads((ROOT / name).read_text())["episodes"]
    for entry in entries:
        r, s = read_episode(entry)
        split = int(entry["id"] in HOLDOUT)
        for t in range(719):
            c = Context(r["steps"][t][s]["observation"])
            sample = t % 4 == 0 and not split
            batches = []
            ranges = []
            for idx in range(len(c.positions)):
                task = next_task(r, t, s, idx)
                a = unit_action(r, t, s, idx)
                p = c.positions[idx]
                if task is None:
                    if initial or a[0] != "PASS":
                        continue
                    task = ("PASS", "", *p, 1)
                if a[0] in E.FARMER_MOVES and p[0] != task[2] and p[1] != task[3]:
                    axis_x[split].append(c.features(idx, task))
                    axis_y[split].append(int(a[0] in ["WEST", "EAST"]))
                if a[0] == "PICKUP" and a[1] == "WHEAT":
                    normalized = ("PICKUP", "WHEAT", *p, 1)
                    qty_x[split].append(c.features(idx, normalized))
                    qty_y[split].append(a[2] if len(a) > 2 else 1)
                if sample:
                    candidates = c.candidates(idx)
                    neg = [z for z in candidates if taskkey(z) != taskkey(task)]
                    start = len(batches)
                    batches.extend(c.features(idx, z) for z in neg)
                    ranges.append((idx, task, start, len(batches)))
            if batches:
                X = np.asarray(batches, dtype=np.float32)
                pred = heads["rank"].decision_function(X)
                for idx, task, lo, hi in ranges:
                    hard_x.append(c.features(idx, task))
                    hard_y.append(1)
                    for j in np.argsort(pred[lo:hi])[-5:] + lo:
                        hard_x.append(X[j])
                        hard_y.append(0)
        print(
            "mined",
            entry["id"],
            "hard",
            len(hard_y),
            "axis",
            len(axis_y[split]),
            flush=True,
        )
    out = {
        "hard_x": np.asarray(hard_x, dtype=np.float32),
        "hard_y": np.asarray(hard_y, dtype=np.float32),
    }
    for name, x, y in [("axis", axis_x, axis_y), ("qty", qty_x, qty_y)]:
        for split in (0, 1):
            out[f"{name}_x{split}"] = np.asarray(x[split], dtype=np.float32)
            out[f"{name}_y{split}"] = np.asarray(y[split], dtype=np.float32)
    np.savez_compressed(
        ART / ("refine-data.npz" if initial else "refine-data-expanded.npz"), **out
    )
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rebuild", action="store_true")
    parser.add_argument("--initial", action="store_true")
    args = parser.parse_args()
    with (ART / "native-models.pkl").open("rb") as f:
        heads = pickle.load(f)
    start = time.time()
    with threadpool_limits(limits=4):
        cache = ART / (
            "refine-data.npz" if args.initial else "refine-data-expanded.npz"
        )
        d = (
            build(heads, args.initial)
            if args.rebuild or not cache.exists()
            else np.load(cache)
        )
        base = np.load(ART / "dataset.npz")
        metrics = {}
        X = np.concatenate([base["rank_x0"], d["hard_x"]])
        y = np.concatenate([base["rank_y0"], d["hard_y"]])
        rank = HistGradientBoostingClassifier(
            max_iter=(360 if args.initial else 400),
            max_leaf_nodes=63,
            max_depth=10,
            min_samples_leaf=30,
            l2_regularization=2,
            learning_rate=0.075,
            early_stopping=False,
            random_state=712,
        )
        rank.fit(X, y)
        heads["rank"] = rank
        metrics["rank_pair_auc"] = float(
            roc_auc_score(base["rank_y1"], rank.predict_proba(base["rank_x1"])[:, 1])
        )
        print(metrics, flush=True)
        axis = HistGradientBoostingClassifier(
            max_iter=100,
            max_leaf_nodes=15,
            max_depth=5,
            min_samples_leaf=25,
            l2_regularization=2,
            learning_rate=0.08,
            early_stopping=False,
            random_state=712,
        )
        axis.fit(d["axis_x0"], d["axis_y0"])
        heads["axis"] = axis
        metrics["movement_axis_accuracy"] = float(
            accuracy_score(d["axis_y1"], axis.predict(d["axis_x1"]))
        )
        metrics["movement_axis_vertical_baseline"] = float(np.mean(d["axis_y1"] == 0))
        qty = HistGradientBoostingRegressor(
            max_iter=100,
            max_leaf_nodes=15,
            max_depth=5,
            min_samples_leaf=20,
            l2_regularization=2,
            learning_rate=0.08,
            early_stopping=False,
            random_state=712,
        )
        qty.fit(d["qty_x0"], d["qty_y0"])
        heads["pickup_wheat"] = qty
        metrics["pickup_wheat_mae"] = float(
            mean_absolute_error(d["qty_y1"], qty.predict(d["qty_x1"]))
        )
    with (ART / "native-models.pkl").open("wb") as f:
        pickle.dump(heads, f)
    exported = {k: export_model(v) for k, v in heads.items()}
    with gzip.open(ROOT / "models.json.gz", "wt") as f:
        json.dump(exported, f)
    for name, m in heads.items():
        X = (
            base["rank_x1"]
            if name == "rank"
            else d["axis_x1"]
            if name == "axis"
            else d["qty_x1"]
            if name == "pickup_wheat"
            else base["sale_x1"]
            if name == "sale"
            else base["macro_x1"]
        )[:100]
        pred = m.decision_function(X) if name in ("rank", "axis") else m.predict(X)
        assert np.allclose(
            pred, TreeModel(exported[name]).predict(X), rtol=1e-10, atol=1e-10
        ), name
    metrics["seconds"] = time.time() - start
    metrics["inference_export_equivalent"] = True
    (ART / "refinement-metrics.json").write_text(json.dumps(metrics, indent=2))
    print(metrics, flush=True)


if __name__ == "__main__":
    main()
