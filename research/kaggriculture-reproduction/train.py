"""Learn task ranking and market behavior, split at whole-episode level."""

import os

os.environ.setdefault("OMP_NUM_THREADS", "4")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
import argparse, collections, gzip, json, pickle, random, time
import numpy as np
from sklearn.ensemble import (
    HistGradientBoostingClassifier,
    HistGradientBoostingRegressor,
)
from sklearn.metrics import mean_absolute_error, roc_auc_score
from threadpoolctl import threadpool_limits
from policy import Context, project_units, sale_features, ANIMALS, E, ROOT

from fetch_data import DEFAULT_DATA

DATA = DEFAULT_DATA
HOLDOUT = {111105944, 111100318, 109448978, 109853569, 110979592, 109662254}
ART = ROOT / "artifacts"
ART.mkdir(exist_ok=True)


def read_episode(entry):
    eid = entry["id"]
    r = json.loads(gzip.decompress((DATA / f"episode-{eid}.json.gz").read_bytes()))
    seat = next(
        a.get("index", 0) for a in entry["agents"] if a["submissionId"] == 56216119
    )
    return r, seat


def unit_action(r, t, s, idx):
    a = r["steps"][t + 1][s]["action"]
    return (
        a.get("farmer", ["PASS"])
        if idx == 0
        else (
            a.get("hands", [])[idx - 1] if len(a.get("hands", [])) >= idx else ["PASS"]
        )
    )


def next_task(r, t, s, idx):
    for j in range(t, min(719, (t // 24 + 1) * 24)):
        farm = r["steps"][j][s]["observation"]["farms"][s]
        if idx > len(farm["hands"]):
            return None
        act = unit_action(r, j, s, idx)
        op = act[0]
        if op in E.FARMER_MOVES:
            continue
        if op == "PASS":
            return None
        x, y = farm["farmer"] if idx == 0 else farm["hands"][idx - 1]
        tile = farm["tiles"][y][x]
        tile = tile if isinstance(tile, dict) else {}
        item = (
            act[1]
            if op in ["PLANT", "PICKUP", "PLACE"]
            else tile.get("crop", tile.get("animal", ""))
        )
        if op in ["DROP", "BUILD_PASTURE", "BUILD_COOP", "DIG"]:
            item = ""
        n = act[2] if len(act) > 2 else 1
        return (op, item, x, y, n)
    return None


def taskkey(task):
    return task[:4]


def dataset():
    rng = random.Random(711)
    manifest = json.loads((ROOT / "sample-manifest.json").read_text())
    rank_x = [[], []]
    rank_y = [[], []]
    sale_x = [[], []]
    sale_y = [[], []]
    macro_x = [[], []]
    macro_y = [[], []]
    coverage = collections.Counter()
    for entry in manifest["episodes"]:
        eid = entry["id"]
        split = int(eid in HOLDOUT)
        r, s = read_episode(entry)
        ev = json.loads(gzip.decompress((DATA / f"events-{eid}.json.gz").read_bytes()))
        sold = collections.Counter(
            (o["step"], o["item"])
            for o in ev["orders"]
            if o["seat"] == s and o["op"] == "SELL"
        )
        for t in range(719):
            obs = r["steps"][t][s]["observation"]
            c = Context(obs)
            action = r["steps"][t + 1][s]["action"]
            _, private = project_units(obs, action)
            for item in E.PRODUCTS:
                q = private["shed"].get(item, 0)
                if q > 0:
                    sale_x[split].append(sale_features(c, item, private))
                    sale_y[split].append(min(q, sold[t, item]) / q)
            if t % 24 in (0, 6, 12, 18):
                end = min(719, (c.day + 1) * 24)
                f = r["steps"][end][s]["observation"]["farms"][s]
                counts = collections.Counter(
                    tile.get("animal", tile.get("crop"))
                    for row in f["tiles"]
                    for tile in row
                    if isinstance(tile, dict)
                )
                macro_x[split].append(c.plan_features)
                macro_y[split].append([counts[a] for a in ANIMALS + list(E.CROPS)])
            if t % 3 != 0 and t >= 24:
                continue
            for idx in range(len(c.positions)):
                task = next_task(r, t, s, idx)
                if task is None:
                    continue
                candidates = c.candidates(idx)
                coverage["goals"] += 1
                matching = next(
                    (z for z in candidates if taskkey(z) == taskkey(task)), None
                )
                if matching:
                    coverage["covered"] += 1
                    task = matching
                # The future destination is a supervised proxy, not a private plan.
                negatives = [z for z in candidates if taskkey(z) != taskkey(task)]
                rng.shuffle(negatives)
                negatives = negatives[:6]
                near = sorted(
                    (z for z in candidates if taskkey(z) != taskkey(task)),
                    key=lambda z: (
                        abs(z[2] - c.positions[idx][0])
                        + abs(z[3] - c.positions[idx][1])
                    ),
                )[:3]
                negatives += near
                rank_x[split].append(c.features(idx, task))
                rank_y[split].append(1)
                for z in negatives:
                    rank_x[split].append(c.features(idx, z))
                    rank_y[split].append(0)
        print(
            "data",
            eid,
            "holdout" if split else "train",
            "rank",
            len(rank_y[split]),
            "sale",
            len(sale_y[split]),
            flush=True,
        )
    out = {}
    for name, x, y in [
        ("rank", rank_x, rank_y),
        ("sale", sale_x, sale_y),
        ("macro", macro_x, macro_y),
    ]:
        for split in (0, 1):
            out[name + "_x" + str(split)] = np.asarray(x[split], dtype=np.float32)
            out[name + "_y" + str(split)] = np.asarray(y[split], dtype=np.float32)
    np.savez_compressed(ART / "dataset.npz", **out)
    (ART / "split.json").write_text(
        json.dumps(
            {
                "holdout_episodes": sorted(HOLDOUT),
                "train_episodes": [
                    e["id"] for e in manifest["episodes"] if e["id"] not in HOLDOUT
                ],
                "destination_coverage": dict(coverage),
                "features_use_only_current_observation": True,
            },
            indent=2,
        )
    )
    return out


def export_model(model):
    trees = []
    for stage in model._predictors:
        for predictor in stage:
            nodes = predictor.nodes
            trees.append(
                {
                    "left": nodes["left"].tolist(),
                    "right": nodes["right"].tolist(),
                    "feature": nodes["feature_idx"].tolist(),
                    "leaf": nodes["is_leaf"].tolist(),
                    "threshold": nodes["num_threshold"].tolist(),
                    "value": nodes["value"].tolist(),
                }
            )
    return {"bias": float(model._baseline_prediction.ravel()[0]), "trees": trees}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rebuild", action="store_true")
    args = parser.parse_args()
    if args.rebuild or not (ART / "dataset.npz").exists():
        d = dataset()
    else:
        d = np.load(ART / "dataset.npz")
    heads = {}
    metrics = {}
    clock = time.time()
    with threadpool_limits(limits=4):
        rank = HistGradientBoostingClassifier(
            max_iter=140,
            max_leaf_nodes=31,
            max_depth=8,
            min_samples_leaf=35,
            l2_regularization=2,
            learning_rate=0.09,
            early_stopping=False,
            random_state=711,
        )
        rank.fit(d["rank_x0"], d["rank_y0"])
        heads["rank"] = rank
        metrics["rank_pair_auc"] = float(
            roc_auc_score(d["rank_y1"], rank.predict_proba(d["rank_x1"])[:, 1])
        )
        print("rank", metrics, flush=True)
        sale = HistGradientBoostingRegressor(
            max_iter=220,
            max_leaf_nodes=31,
            max_depth=8,
            min_samples_leaf=25,
            l2_regularization=2,
            learning_rate=0.07,
            early_stopping=False,
            random_state=711,
        )
        sale.fit(d["sale_x0"], d["sale_y0"])
        heads["sale"] = sale
        metrics["sale_fraction_mae"] = float(
            mean_absolute_error(d["sale_y1"], sale.predict(d["sale_x1"]))
        )
        print("sale", metrics, flush=True)
        for i, animal in enumerate(ANIMALS + list(E.CROPS)):
            model = HistGradientBoostingRegressor(
                max_iter=100,
                max_leaf_nodes=15,
                max_depth=5,
                min_samples_leaf=12,
                l2_regularization=2,
                learning_rate=0.08,
                early_stopping=False,
                random_state=711,
            )
            model.fit(d["macro_x0"], d["macro_y0"][:, i])
            heads[("animal_" if animal in ANIMALS else "crop_") + animal] = model
            metrics["animal_" + animal + "_mae"] = float(
                mean_absolute_error(d["macro_y1"][:, i], model.predict(d["macro_x1"]))
            )
    with (ART / "native-models.pkl").open("wb") as f:
        pickle.dump(heads, f)
    exported = {name: export_model(model) for name, model in heads.items()}
    with gzip.open(ROOT / "models.json.gz", "wt") as f:
        json.dump(exported, f)
    from policy import TreeModel

    for name, m in heads.items():
        X = (
            d["rank_x1"][:100]
            if name == "rank"
            else d["sale_x1"][:100]
            if name == "sale"
            else d["macro_x1"][:100]
        )
        expected = m.decision_function(X) if name == "rank" else m.predict(X)
        actual = TreeModel(exported[name]).predict(X)
        assert np.allclose(expected, actual, rtol=1e-10, atol=1e-10), name
    metrics["training_seconds"] = time.time() - clock
    metrics["inference_export_equivalent"] = True
    (ART / "training-metrics.json").write_text(json.dumps(metrics, indent=2))
    print(metrics, flush=True)


if __name__ == "__main__":
    main()
