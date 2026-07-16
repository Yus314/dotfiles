from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

import yaml


SCRIPT = Path(__file__).parents[1] / "scripts/profile_registry_check.py"
SPEC = importlib.util.spec_from_file_location("profile_registry_check", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ProfileRegistryCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name) / "home"
        self.profile_root = self.home / ".hermes"
        self.profile_root.mkdir(parents=True)
        (self.profile_root / "config.yaml").write_text(
            yaml.safe_dump(
                {
                    "memory": {"provider": "honcho", "memory_enabled": True},
                    "kanban": {
                        "dispatch_in_gateway": True,
                        "auto_decompose": True,
                    },
                    "skills": {
                        "external_dirs": [
                            str(
                                self.home
                                / ".local/share/hermes/shared-skills/common"
                            ),
                            str(
                                self.home
                                / ".local/share/hermes/shared-skills/orchestration"
                            ),
                        ]
                    },
                }
            )
        )
        (self.profile_root / "profile.yaml").write_text(
            yaml.safe_dump({"description": "Control-plane profile"})
        )
        (self.profile_root / "SOUL.md").write_text("# Soul\n")
        self.registry_path = Path(self.temp.name) / "profile-registry.json"
        self.registry = {
            "schema_version": 1,
            "control_plane": "default",
            "profiles": {
                "default": {
                    "role": "control plane",
                    "primary_domains": ["routing"],
                    "non_goals": ["domain raw data"],
                    "canonical_paths": ["~/org"],
                    "summary_path": None,
                    "memory_provider": "honcho",
                    "shared_skill_groups": ["common", "orchestration"],
                    "gateway_expected": "running",
                    "kanban_role": "leader",
                }
            },
            "routing": {
                "work": {"primary": "default", "coordination": []}
            },
        }
        self.write_registry()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_registry(self) -> None:
        self.registry_path.write_text(json.dumps(self.registry))

    def validate(self, gateway: str = "running") -> list[str]:
        return MODULE.validate(
            self.home,
            self.registry_path,
            gateway_state=lambda _profile: gateway,
        )

    def test_valid_registry_matches_live_profile(self) -> None:
        self.assertEqual(self.validate(), [])

    def test_detects_shared_group_drift(self) -> None:
        self.registry["profiles"]["default"]["shared_skill_groups"] = ["common"]
        self.write_registry()
        self.assertTrue(
            any("shared skill groups drift" in error for error in self.validate())
        )

    def test_detects_missing_description_and_unknown_route(self) -> None:
        (self.profile_root / "profile.yaml").write_text("{}\n")
        self.registry["routing"]["work"]["coordination"] = ["missing"]
        self.write_registry()
        errors = self.validate()
        self.assertTrue(any("missing profile description" in error for error in errors))
        self.assertTrue(any("unknown profiles" in error for error in errors))

    def test_detects_gateway_state_drift(self) -> None:
        errors = self.validate(gateway="stopped")
        self.assertTrue(any("gateway state drift" in error for error in errors))

    def test_detects_dispatcher_policy_drift(self) -> None:
        config = yaml.safe_load((self.profile_root / "config.yaml").read_text())
        config["kanban"]["dispatch_in_gateway"] = False
        (self.profile_root / "config.yaml").write_text(yaml.safe_dump(config))
        self.assertTrue(
            any("kanban.dispatch_in_gateway drift" in error for error in self.validate())
        )

    def test_rejects_unknown_control_plane(self) -> None:
        self.registry["control_plane"] = "missing"
        self.write_registry()
        self.assertTrue(
            any("control_plane references unknown" in error for error in self.validate())
        )

    def test_untrusted_same_basename_does_not_satisfy_shared_group(self) -> None:
        config = yaml.safe_load((self.profile_root / "config.yaml").read_text())
        config["skills"]["external_dirs"] = [
            "/tmp/untrusted/common",
            "/tmp/untrusted/orchestration",
        ]
        (self.profile_root / "config.yaml").write_text(yaml.safe_dump(config))
        self.assertTrue(
            any("shared skill groups drift" in error for error in self.validate())
        )

    def test_rejects_invalid_gateway_expectation(self) -> None:
        self.registry["profiles"]["default"]["gateway_expected"] = "sometimes"
        self.write_registry()
        self.assertTrue(
            any("gateway_expected must be" in error for error in self.validate())
        )


if __name__ == "__main__":
    unittest.main()
