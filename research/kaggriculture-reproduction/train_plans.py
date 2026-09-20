"""Fit daily crop/livestock targets using broader, disjoint public training games."""

import os

os.environ.setdefault("OMP_NUM_THREADS", "4")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
import collections, gzip, json, pickle
import numpy as np
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.metrics import mean_absolute_error
from threadpoolctl import threadpool_limits
from train import HOLDOUT, ART, read_episode, export_model
from policy import ROOT, Context, ANIMALS, CROPS, TreeModel


def main():
    entries = []
    for f in ["sample-manifest.json", "additional-train-manifest.json"]:
        entries += json.loads((ROOT / f).read_text())["episodes"]
    xs = [[], []]
    ys = [[], []]
    for entry in entries:
        r, s = read_episode(entry)
        split = int(entry["id"] in HOLDOUT)
        for t in range(0, 719, 6):
            c = Context(r["steps"][t][s]["observation"])
            end = min(719, (c.day + 1) * 24)
            obs = r["steps"][end][s]["observation"]
            counts = collections.Counter(
                z.get("animal", z.get("crop"))
                for row in obs["farms"][s]["tiles"]
                for z in row
                if isinstance(z, dict)
            )
            for animal in ANIMALS:
                counts[animal] += obs["private"]["shed"].get(animal, 0) + sum(
                    inv.get(animal, 0) for inv in obs["private"]["inventories"]
                )
            xs[split].append(c.plan_features)
            ys[split].append([counts[a] for a in ANIMALS + CROPS])
        print("plans", entry["id"], "development" if split else "train", flush=True)
    X = [np.asarray(x, dtype=np.float32) for x in xs]
    Y = [np.asarray(y, dtype=np.float32) for y in ys]
    with (ART / "native-models.pkl").open("rb") as f:
        heads = pickle.load(f)
    metrics = {}
    with threadpool_limits(limits=4):
        for i, item in enumerate(ANIMALS + CROPS):
            model = HistGradientBoostingRegressor(
                max_iter=140,
                max_leaf_nodes=25,
                max_depth=7,
                min_samples_leaf=12,
                l2_regularization=2,
                learning_rate=0.07,
                early_stopping=False,
                random_state=713,
            )
            model.fit(X[0], Y[0][:, i])
            name = ("animal_" if item in ANIMALS else "crop_") + item
            heads[name] = model
            metrics[name + "_mae"] = float(
                mean_absolute_error(Y[1][:, i], model.predict(X[1]))
            )
            assert np.allclose(
                model.predict(X[1][:100]),
                TreeModel(export_model(model)).predict(X[1][:100]),
                atol=1e-10,
                rtol=1e-10,
            )
    with (ART / "native-models.pkl").open("wb") as f:
        pickle.dump(heads, f)
    with gzip.open(ROOT / "models.json.gz", "wt") as f:
        json.dump({k: export_model(v) for k, v in heads.items()}, f)
    metrics["training_episodes"] = [e["id"] for e in entries if e["id"] not in HOLDOUT]
    metrics["development_episodes"] = sorted(HOLDOUT)
    (ART / "planning-metrics.json").write_text(json.dumps(metrics, indent=2))
    print(metrics, flush=True)


if __name__ == "__main__":
    main()
