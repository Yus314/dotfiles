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
                            str(
                                self.home
                                / ".local/share/hermes/shared-skills/usage-ops"
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
        (self.profile_root / "honcho.json").write_text(
            json.dumps({"workspace": "general-shared"})
        )
        self.registry_path = Path(self.temp.name) / "profile-registry.json"
        self.registry = {
            "schema_version": 2,
            "control_plane": "default",
            "information_exchange": {
                "semantic_memory": {
                    "general_shared_workspace": "general-shared",
                    "allowed_content": ["stable cross-domain facts"],
                    "forbidden_content": ["domain raw data"],
                },
                "weekly_summary": {
                    "schema_family": "weekly_summary",
                    "schema_version": 1,
                    "required_fields": [
                        "schema_family",
                        "schema_version",
                        "owner_profile",
                        "generated_at",
                        "coverage_start",
                        "coverage_end",
                        "source_watermark",
                        "status",
                    ],
                },
                "handoff": {
                    "schema_family": "cross_profile_handoff",
                    "schema_version": 2,
                    "required_fields": [
                        "schema_family",
                        "schema_version",
                        "handoff_id",
                        "source_profile",
                        "target_profiles",
                        "purpose",
                        "generated_at",
                        "valid_until",
                        "scope",
                        "status",
                        "source_refs",
                        "source_health",
                        "sensitivity",
                        "raw_data_included",
                        "retention_class",
                        "supersedes",
                        "assumptions",
                        "uncertainties",
                    ],
                    "optional_fields": [
                        "in_reply_to",
                        "requested_fields",
                        "returned_fields",
                        "response_deadline",
                        "hop_count",
                        "max_hops",
                    ],
                    "allowed_purposes": ["compact-status", "review-request", "consultation-response"],
                    "sensitivity_levels": ["ordinary", "sensitive", "restricted"],
                    "retention_classes": ["transient", "promotable", "durable"],
                    "destination_sensitivity": {"default": ["ordinary"]},
                    "raw_data_default": "forbidden",
                },
                "consultation": {
                    "schema_version": 1,
                    "max_hops": 1,
                    "routes": [],
                },
                "kanban": {"content_policy": "redacted-work-orders-only"},
            },
            "profiles": {
                "default": {
                    "role": "control plane",
                    "primary_domains": ["routing"],
                    "non_goals": ["domain raw data"],
                    "canonical_paths": ["~/org"],
                    "summary_path": None,
                    "summary_policy": "none",
                    "memory_provider": "honcho",
                    "memory_workspace": "general-shared",
                    "memory_sharing_class": "general-shared",
                    "shared_skill_groups": ["common", "orchestration", "usage-ops"],
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

    def add_food_profile(self) -> Path:
        root = self.home / ".hermes/profiles/food"
        root.mkdir(parents=True)
        (root / "config.yaml").write_text(
            yaml.safe_dump(
                {
                    "memory": {"provider": "honcho", "memory_enabled": True},
                    "kanban": {
                        "dispatch_in_gateway": False,
                        "auto_decompose": False,
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
        (root / "profile.yaml").write_text(
            yaml.safe_dump({"description": "Food specialist"})
        )
        (root / "SOUL.md").write_text("# Food\n")
        self.registry["profiles"]["food"] = {
            "role": "food specialist",
            "primary_domains": ["meal logs"],
            "non_goals": ["general raw-data sharing"],
            "canonical_paths": ["~/org/food"],
            "summary_path": "~/org/food/weekly/{week}.md",
            "summary_policy": "on-demand",
            "memory_provider": "honcho",
            "memory_workspace": "hermes-food",
            "memory_sharing_class": "sensitive-isolated",
            "memory_policy_reason": "food memory remains isolated",
            "shared_skill_groups": ["common", "orchestration"],
            "gateway_expected": "running",
            "kanban_role": "domain worker",
        }
        self.write_registry()
        return root

    def validate(self, gateway: str = "running") -> list[str]:
        return MODULE.validate(
            self.home,
            self.registry_path,
            gateway_state=lambda _profile: gateway,
        )

    def test_valid_registry_matches_live_profile(self) -> None:
        self.assertEqual(self.validate(), [])

    def test_detects_shared_group_drift(self) -> None:
        self.registry["profiles"]["default"]["shared_skill_groups"] = [
            "common",
            "orchestration",
        ]
        self.write_registry()
        self.assertTrue(
            any("shared skill groups drift" in error for error in self.validate())
        )

    def test_rejects_unknown_group_even_when_live_config_matches(self) -> None:
        unknown_path = str(
            self.home / ".local/share/hermes/shared-skills/typo-group"
        )
        config_path = self.profile_root / "config.yaml"
        config = yaml.safe_load(config_path.read_text())
        config["skills"]["external_dirs"].append(unknown_path)
        config_path.write_text(yaml.safe_dump(config))
        self.registry["profiles"]["default"]["shared_skill_groups"].append(
            "typo-group"
        )
        self.write_registry()
        errors = self.validate()
        self.assertTrue(any("unknown shared skill groups" in error for error in errors))
        self.assertFalse(any("shared skill groups drift" in error for error in errors))

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

    def test_validates_explicit_honcho_workspace(self) -> None:
        self.registry["profiles"]["default"]["memory_workspace"] = "private-default"
        self.registry["information_exchange"]["semantic_memory"][
            "general_shared_workspace"
        ] = "private-default"
        self.write_registry()
        (self.profile_root / "honcho.json").write_text(
            json.dumps(
                {
                    "workspace": "fallback",
                    "hosts": {"hermes": {"workspace": "private-default"}},
                }
            )
        )
        self.assertEqual(self.validate(), [])

        (self.profile_root / "honcho.json").write_text(
            json.dumps({"workspace": "wrong"})
        )
        self.assertTrue(
            any("Honcho workspace drift" in error for error in self.validate())
        )

    def test_profile_honcho_config_falls_back_to_default(self) -> None:
        profile = self.home / ".hermes/profiles/career"
        profile.mkdir(parents=True)
        self.assertEqual(
            MODULE.honcho_config_path(self.home, profile),
            self.profile_root / "honcho.json",
        )

    def test_sensitive_food_requires_profile_local_honcho_config(self) -> None:
        self.add_food_profile()
        errors = self.validate()
        self.assertTrue(
            any(
                "food: Honcho workspace drift" in error
                and "actual='general-shared'" in error
                for error in errors
            )
        )

    def test_sensitive_food_uses_profile_host_workspace(self) -> None:
        root = self.add_food_profile()
        (root / "honcho.json").write_text(
            json.dumps(
                {
                    "workspace": "fallback-wrong",
                    "hosts": {"hermes_food": {"workspace": "hermes-food"}},
                }
            )
        )
        self.assertEqual(self.validate(), [])

        (root / "honcho.json").write_text(
            json.dumps(
                {
                    "workspace": "hermes-food",
                    "hosts": {"hermes_food": {"workspace": "general-shared"}},
                }
            )
        )
        self.assertTrue(
            any("food: Honcho workspace drift" in error for error in self.validate())
        )

    def test_rejects_memory_sharing_class_provider_mismatch(self) -> None:
        self.registry["profiles"]["default"]["memory_sharing_class"] = "profile-local"
        self.write_registry()
        self.assertTrue(
            any("memory sharing class" in error for error in self.validate())
        )

    def test_requires_information_exchange_contract(self) -> None:
        del self.registry["information_exchange"]
        self.write_registry()
        self.assertTrue(
            any("information_exchange" in error for error in self.validate())
        )

    def test_rejects_incomplete_handoff_contract(self) -> None:
        self.registry["information_exchange"]["handoff"]["required_fields"].remove(
            "valid_until"
        )
        self.write_registry()
        self.assertTrue(any("handoff required_fields" in error for error in self.validate()))

    def test_rejects_incomplete_consultation_contract(self) -> None:
        self.registry["information_exchange"]["handoff"]["optional_fields"].remove(
            "in_reply_to"
        )
        self.registry["information_exchange"]["consultation"]["routes"] = [
            {
                "source": "default",
                "target": "missing",
                "max_ttl_hours": 999,
                "allowed_requested_fields": ["status"],
            }
        ]
        self.write_registry()
        errors = self.validate()
        self.assertTrue(any("optional_fields" in error for error in errors))
        self.assertTrue(any("invalid source or target" in error for error in errors))
        self.assertTrue(any("max_ttl_hours" in error for error in errors))

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

    def test_rejects_invalid_summary_policy(self) -> None:
        self.registry["profiles"]["default"]["summary_policy"] = "always-missing"
        self.write_registry()
        self.assertTrue(
            any("summary_policy must be" in error for error in self.validate())
        )

    def test_requires_reason_for_blocked_summary_policy(self) -> None:
        self.registry["profiles"]["default"]["summary_policy"] = "blocked"
        self.write_registry()
        self.assertTrue(
            any("blocked summary_policy requires" in error for error in self.validate())
        )

    def test_rejects_non_string_blocked_summary_reason(self) -> None:
        self.registry["profiles"]["default"].update(
            summary_policy="blocked", summary_policy_reason=["not", "text"]
        )
        self.write_registry()
        self.assertTrue(
            any("blocked summary_policy requires" in error for error in self.validate())
        )

    def test_rejects_old_registry_schema(self) -> None:
        self.registry["schema_version"] = 1
        self.write_registry()
        self.assertTrue(any("schema_version must be 2" in error for error in self.validate()))


class DeclarativeFoodConfigTests(unittest.TestCase):
    def test_food_registry_and_honcho_source_share_isolated_workspace(self) -> None:
        source_root = Path(__file__).parents[1]
        registry = json.loads((source_root / "profile-registry.json").read_text())
        config = json.loads(
            (source_root / "profile-configs/food/honcho.json").read_text()
        )
        food = registry["profiles"]["food"]
        self.assertEqual(food["memory_sharing_class"], "sensitive-isolated")
        self.assertEqual(food["memory_workspace"], "hermes-food")
        self.assertEqual(config["workspace"], "hermes-food")
        self.assertEqual(
            config["hosts"]["hermes_food"]["workspace"], "hermes-food"
        )


if __name__ == "__main__":
    unittest.main()
