"""Extend market imitation and compare fraction and absolute-quantity heads."""

import os

os.environ.setdefault("OMP_NUM_THREADS", "4")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
import argparse, collections, gzip, json, pickle
import numpy as np
from sklearn.ensemble import HistGradientBoostingRegressor
from threadpoolctl import threadpool_limits
from train import DATA, ART, read_episode, export_model
from policy import ROOT, Context, project_units, sale_features, E, TreeModel


def build():
    base = np.load(ART / "dataset.npz")
    xs = []
    ys = []
    for e in json.loads((ROOT / "additional-train-manifest.json").read_text())[
        "episodes"
    ]:
        r, s = read_episode(e)
        ev = json.loads(
            gzip.decompress((DATA / f"events-{e['id']}.json.gz").read_bytes())
        )
        sold = collections.Counter(
            (o["step"], o["item"])
            for o in ev["orders"]
            if o["seat"] == s and o["op"] == "SELL"
        )
        for t in range(719):
            obs = r["steps"][t][s]["observation"]
            c = Context(obs)
            _, private = project_units(obs, r["steps"][t + 1][s]["action"])
            for item in E.PRODUCTS:
                q = private["shed"].get(item, 0)
                if q > 0:
                    xs.append(sale_features(c, item, private))
                    ys.append(min(q, sold[t, item]) / q)
        print("sales", e["id"], len(ys), flush=True)
    d = {
        "x0": np.concatenate([base["sale_x0"], np.asarray(xs, dtype=np.float32)]),
        "y0": np.concatenate([base["sale_y0"], np.asarray(ys, dtype=np.float32)]),
        "x1": base["sale_x1"],
        "y1": base["sale_y1"],
    }
    np.savez_compressed(ART / "sales-expanded.npz", **d)
    return d


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-only", action="store_true")
    args = parser.parse_args()
    d = (
        np.load(ART / "sales-expanded.npz")
        if (ART / "sales-expanded.npz").exists()
        else build()
    )
    if args.build_only:
        return
    with (ART / "native-models.pkl").open("rb") as f:
        heads = pickle.load(f)
    q0 = d["x0"][:, -31]
    q1 = d["x1"][:, -31]
    target0 = np.rint(d["y0"] * q0)
    target1 = np.rint(d["y1"] * q1)
    metrics = {}
    candidates = {"fraction_previous": heads["sale"]}
    with threadpool_limits(limits=4):
        for mode in ["fraction", "quantity"]:
            model = HistGradientBoostingRegressor(
                loss="squared_error" if mode == "fraction" else "absolute_error",
                max_iter=300,
                max_leaf_nodes=31,
                max_depth=8,
                min_samples_leaf=25,
                l2_regularization=2,
                learning_rate=0.075,
                early_stopping=False,
                random_state=714,
            )
            model.fit(d["x0"], d["y0"] if mode == "fraction" else target0)
            candidates[mode] = model
        for name, m in candidates.items():
            pred = m.predict(d["x1"])
            amount = np.clip(np.rint(pred if name == "quantity" else pred * q1), 0, q1)
            metrics[name] = {
                "quantity_mae": float(np.mean(np.abs(amount - target1))),
                "quantity_exact": float(np.mean(amount == target1)),
            }
    # Absolute-quantity imitation stalled in autonomous development rollouts.
    # Use the fraction head, which had the lowest development quantity MAE.
    chosen = "fraction"
    if chosen == "quantity":
        heads["sale_quantity"] = candidates[chosen]
    else:
        heads.pop("sale_quantity", None)
        heads["sale"] = candidates[chosen]
    for name, m in candidates.items():
        assert np.allclose(
            m.predict(d["x1"][:100]),
            TreeModel(export_model(m)).predict(d["x1"][:100]),
            atol=1e-10,
            rtol=1e-10,
        )
    with (ART / "native-models.pkl").open("wb") as f:
        pickle.dump(heads, f)
    with gzip.open(ROOT / "models.json.gz", "wt") as f:
        json.dump({k: export_model(v) for k, v in heads.items()}, f)
    metrics["selected"] = chosen
    metrics["inference_export_equivalent"] = True
    (ART / "sales-metrics.json").write_text(json.dumps(metrics, indent=2))
    print(metrics, flush=True)


if __name__ == "__main__":
    main()
