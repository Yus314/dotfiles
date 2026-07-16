from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

import yaml


SCRIPT = Path(__file__).parents[1] / "scripts/kanban_dispatch_config.py"
SPEC = importlib.util.spec_from_file_location("kanban_dispatch_config", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class KanbanDispatchConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.registry = self.home / "registry.json"
        self.registry.write_text(
            json.dumps(
                {
                    "control_plane": "default",
                    "profiles": {"default": {}, "finance": {}},
                }
            )
        )
        for profile in ("default", "finance"):
            root = MODULE.profile_root(self.home, profile)
            root.mkdir(parents=True)
            (root / "config.yaml").write_text(
                yaml.safe_dump(
                    {
                        "unrelated": {"keep": True},
                        "kanban": {
                            "dispatch_in_gateway": True,
                            "auto_decompose": True,
                            "dispatch_interval_seconds": 60,
                        },
                    },
                    sort_keys=False,
                )
            )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_configure_leaves_only_control_plane_dispatching(self) -> None:
        self.assertTrue(MODULE.check(self.home, self.registry))
        changed = MODULE.configure(self.home, self.registry)
        self.assertEqual(changed, ["finance"])
        self.assertEqual(MODULE.check(self.home, self.registry), [])
        default = yaml.safe_load((MODULE.profile_root(self.home, "default") / "config.yaml").read_text())
        finance = yaml.safe_load((MODULE.profile_root(self.home, "finance") / "config.yaml").read_text())
        self.assertTrue(default["kanban"]["dispatch_in_gateway"])
        self.assertFalse(finance["kanban"]["dispatch_in_gateway"])
        self.assertTrue(finance["unrelated"]["keep"])
        self.assertEqual(finance["kanban"]["dispatch_interval_seconds"], 60)

    def test_configure_is_idempotent(self) -> None:
        MODULE.configure(self.home, self.registry)
        self.assertEqual(MODULE.configure(self.home, self.registry), [])

    def test_preflight_failure_does_not_partially_update_earlier_profile(self) -> None:
        registry = json.loads(self.registry.read_text())
        registry["profiles"]["career"] = {}
        self.registry.write_text(json.dumps(registry))
        career_root = MODULE.profile_root(self.home, "career")
        career_root.mkdir(parents=True)
        career_config = {
            "kanban": {"dispatch_in_gateway": True, "auto_decompose": True}
        }
        (career_root / "config.yaml").write_text(
            yaml.safe_dump(career_config, sort_keys=False)
        )
        (MODULE.profile_root(self.home, "finance") / "config.yaml").write_text(
            "kanban: not-a-mapping\n"
        )

        with self.assertRaises(ValueError):
            MODULE.configure(self.home, self.registry)

        unchanged = yaml.safe_load((career_root / "config.yaml").read_text())
        self.assertTrue(unchanged["kanban"]["dispatch_in_gateway"])
        self.assertTrue(unchanged["kanban"]["auto_decompose"])

    def test_invalid_control_plane_is_rejected(self) -> None:
        self.registry.write_text(
            json.dumps({"control_plane": "missing", "profiles": {"default": {}}})
        )
        with self.assertRaises(ValueError):
            MODULE.configure(self.home, self.registry)


if __name__ == "__main__":
    unittest.main()
