"""Regression cases for task-label compatibility and scarce-task allocation."""

import importlib.util
import itertools
import unittest
from unittest.mock import patch
import numpy as np
import policy as baseline
from train import read_episode, next_task
import json


def candidate():
    spec = importlib.util.spec_from_file_location(
        "scheduler_candidate", baseline.ROOT / "baselines/v9-candidate/policy.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestScheduler(unittest.TestCase):
    def test_crop_dig_candidate_matches_training_label(self):
        p = candidate()
        entry = next(
            e
            for e in json.loads((baseline.ROOT / "sample-manifest.json").read_text())[
                "episodes"
            ]
            if e["id"] == 111105944
        )
        r, s = read_episode(entry)
        checked = 0
        for t in range(719):
            c = p.Context(r["steps"][t][s]["observation"])
            action = r["steps"][t + 1][s]["action"]
            for idx, a in enumerate([action["farmer"]] + action["hands"]):
                x, y = c.positions[idx]
                tile = c.tiles[y][x]
                if a[0] != "DIG" or not isinstance(tile, dict) or "crop" not in tile:
                    continue
                label = next_task(r, t, s, idx)
                with patch.dict(p.OPTIONS, {"canonical_dig": False}):
                    before = c.candidates(idx)
                with patch.dict(p.OPTIONS, {"canonical_dig": True}):
                    after = c.candidates(idx)
                self.assertNotIn(label[:4], [z[:4] for z in before])
                self.assertIn(label[:4], [z[:4] for z in after])
                from train_scheduler import normalize_dig_rows

                old_feature = np.asarray(
                    [c.features(idx, ("DIG", tile["crop"], x, y, 1))], dtype=np.float32
                )
                opcol = len(c.global_features)
                normalize_dig_rows(old_feature, opcol, opcol + 1, p.OP_ID["DIG"])
                np.testing.assert_array_equal(
                    old_feature[0], np.asarray(c.features(idx, label), dtype=np.float32)
                )
                self.assertEqual(
                    [z for z in before if z[0] != "DIG"],
                    [z for z in after if z[0] != "DIG"],
                )
                checked += 1
        self.assertGreater(checked, 0)

    def test_flexible_worker_does_not_take_only_good_task(self):
        p = candidate()
        tasks = [("WATER", "WHEAT", 0, 0, 1), ("WATER", "WHEAT", 1, 0, 1)]
        scores = [[10.0, 9.0], [9.0, 0.0]]

        class Model:
            def predict(self, features):
                return np.array([scores[i][j] for i, j in features])

        class Context:
            positions = [(0, 0), (0, 0)]
            seat = 0
            step = 5
            hour = 5
            day = 0
            targets = None
            shed = {}
            seeds = {}
            tiles = [[None, None]]
            invs = [{}, {}]

            def candidates(self, idx):
                return tasks

            def features(self, idx, task):
                return [idx, tasks.index(task)]

        c = Context()
        with patch.dict(p.OPTIONS, {"assignment": "regret"}):
            selected, _ = p.choose_units(c, Model())
        value = sum(scores[i][tasks.index(t)] for i, t in enumerate(selected))
        optimum = max(
            sum(scores[i][j] for i, j in enumerate(order))
            for order in itertools.permutations(range(2))
        )
        self.assertEqual(value, optimum)
        self.assertEqual(len({t[:4] for t in selected}), 2)
        with patch.dict(p.OPTIONS, {"assignment": "global"}):
            old, _ = p.choose_units(c, Model())
        self.assertLess(
            sum(scores[i][tasks.index(t)] for i, t in enumerate(old)), value
        )


if __name__ == "__main__":
    unittest.main()
