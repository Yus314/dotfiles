import copy, gzip, importlib.util, json, unittest
from unittest.mock import patch
import numpy as np
import engine as E
import policy
from evaluate import Node, node
from fetch_data import DEFAULT_DATA

DATA = DEFAULT_DATA


def candidate_policy():
    spec = importlib.util.spec_from_file_location(
        "candidate_policy", policy.ROOT / "baselines/v8-candidate/policy.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestPolicy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.replay = json.loads(
            gzip.decompress((DATA / "episode-111105944.json.gz").read_bytes())
        )

    def test_pinned_engine_reproduces_every_transition(self):
        r = self.replay
        state = node(copy.deepcopy(r["steps"][0]))
        env = Node(
            configuration=node(r["configuration"]), info=node(r["info"]), done=False
        )
        for t in range(719):
            for s in range(2):
                state[s].observation.step = t
                state[s].action = node(r["steps"][t + 1][s]["action"])
            E.interpreter(state, env)
            for s in range(2):
                for key in ["farms", "private", "market", "town", "day", "hour"]:
                    self.assertEqual(
                        state[s].observation[key],
                        r["steps"][t + 1][s]["observation"][key],
                        (t, s, key),
                    )
        self.assertEqual([s.reward for s in state], [94988, 96230])

    def test_observation_not_mutated_and_opening_exact(self):
        for t in [0, 1]:
            obs = copy.deepcopy(self.replay["steps"][t][1]["observation"])
            before = copy.deepcopy(obs)
            action = policy.agent(obs)
            self.assertEqual(action, self.replay["steps"][t + 1][1]["action"])
            self.assertEqual(obs, before)

    def test_feature_schema_and_hidden_fields(self):
        obs = copy.deepcopy(self.replay["steps"][300][1]["observation"])
        a = policy.Context(obs)
        obs["remainingOverageTime"] = 0
        obs["debug_hidden_episode_id"] = 123456
        b = policy.Context(obs)
        self.assertEqual(a.global_features, b.global_features)
        widths = set(
            len(a.features(i, t))
            for i in range(len(a.positions))
            for t in a.candidates(i)
        )
        self.assertEqual(len(widths), 1)

    def test_final_day_candidates_can_return_harvest(self):
        obs = copy.deepcopy(self.replay["steps"][708][1]["observation"])
        c = policy.Context(obs)
        for i in range(len(c.positions)):
            for t in c.candidates(i):
                if t[0] in ["HARVEST", "COLLECT_FERTILIZER"]:
                    self.assertLessEqual(
                        policy.distance(c.positions[i], t[2:4])
                        + policy.shed_distance(t[2:4])
                        + 2,
                        23 - c.hour,
                    )

    def test_last_two_decisions_allow_harvest_then_drop(self):
        obs = copy.deepcopy(self.replay["steps"][717][1]["observation"])
        obs["farms"][1]["farmer"] = [4, 4]
        obs["farms"][1]["tiles"][4][4] = E._new_plant("MELON", 10, 24)
        obs["farms"][1]["tiles"][4][4]["yield_units"] = 6
        c = policy.Context(obs)
        self.assertIn(("HARVEST", "MELON", 4, 4, 1), c.candidates(0))
        obs["hour"] = 22
        if "step" in obs:
            obs["step"] = 718
        c = policy.Context(obs)
        self.assertNotIn(("HARVEST", "MELON", 4, 4, 1), c.candidates(0))

    def test_export_is_finite(self):
        if not (policy.ROOT / "models.json.gz").exists():
            self.skipTest("models not yet trained")
        c = policy.Context(self.replay["steps"][300][1]["observation"])
        tasks = c.candidates(0)
        scores = policy.models()["rank"].predict([c.features(0, t) for t in tasks])
        self.assertTrue(np.isfinite(scores).all())

    def test_animal_budget_survives_transfers_losses_and_restart(self):
        policy = candidate_policy()
        obs = copy.deepcopy(self.replay["steps"][0][1]["observation"])
        policy._ANIMAL_MEMORY.clear()
        obs["step"] = 0
        self.assertEqual(policy.observe_animal_purchases(obs)["COW"], 0)
        obs["step"] = 1
        obs["private"]["shed"]["COW"] = 1
        self.assertEqual(policy.observe_animal_purchases(obs)["COW"], 1)
        obs["step"] = 2
        obs["private"]["shed"]["COW"] = 0
        obs["private"]["inventories"][0]["COW"] = 1
        self.assertEqual(policy.observe_animal_purchases(obs)["COW"], 1)
        obs["step"] = 3
        obs["private"]["inventories"][0]["COW"] = 0
        obs["farms"][1]["tiles"][0][0] = {"animal": "COW"}
        self.assertEqual(policy.observe_animal_purchases(obs)["COW"], 1)
        obs["step"] = 4
        obs["farms"][1]["tiles"][0][0] = None
        self.assertEqual(policy.observe_animal_purchases(obs)["COW"], 1)
        # A second call cannot erase the loss history; a new game must reset it.
        self.assertEqual(policy.observe_animal_purchases(obs)["COW"], 1)
        obs["step"] = 0
        self.assertEqual(policy.observe_animal_purchases(obs)["COW"], 0)

    def test_animal_budget_blocks_replacement_but_allows_expansion(self):
        policy = candidate_policy()

        class Constant:
            def __init__(self, n):
                self.n = n

            def predict(self, rows):
                return [self.n] * len(rows)

        obs = copy.deepcopy(self.replay["steps"][200][1]["observation"])
        farm, private = obs["farms"][1], obs["private"]
        farm["money"] = 20000
        farm["tiles"] = [[None for _ in range(10)] for _ in range(10)]
        private["shed"] = {i: 0 for i in private["shed"]}
        private["shed"]["COW"] = 1
        private["inventories"] = [{} for _ in private["inventories"]]
        heads = {"animal_" + a: Constant(0) for a in policy.ANIMALS}
        heads["animal_COW"] = Constant(2)
        heads["sale"] = Constant(0)
        c = policy.Context(obs)
        units = [["PASS"] for _ in c.positions]
        tasks = [("PASS", "", *p, 1) for p in c.positions]
        policy._ANIMAL_MEMORY[c.seat] = {
            "purchased": {"COW": 2, "SHEEP": 0, "GOOSE": 0}
        }
        with patch.dict(policy.OPTIONS, {"animal_purchase_cap": False}):
            self.assertIn(
                ["BUY_ANIMAL", "COW", 1], policy.market_orders(c, units, tasks, heads)
            )
        with patch.dict(policy.OPTIONS, {"animal_purchase_cap": True}):
            self.assertFalse(
                any(
                    o[0] == "BUY_ANIMAL"
                    for o in policy.market_orders(c, units, tasks, heads)
                )
            )
            heads["animal_COW"] = Constant(3)
            self.assertIn(
                ["BUY_ANIMAL", "COW", 1], policy.market_orders(c, units, tasks, heads)
            )


if __name__ == "__main__":
    unittest.main()
