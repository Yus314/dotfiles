from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SOURCE_ROOT = Path(__file__).parents[1]
SCRIPT = SOURCE_ROOT / "scripts/default_continuity_check.py"
SPEC = importlib.util.spec_from_file_location("default_continuity_check", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class DefaultContinuityCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self.contract = json.loads(
            (SOURCE_ROOT / "default-continuity-contract-v1.json").read_text()
        )
        self.registry = json.loads((SOURCE_ROOT / "profile-registry.json").read_text())
        self.honcho = {
            "workspace": "fallback",
            "peerName": "fallback-user",
            "secretToken": "must-not-appear",
            "hosts": {
                "hermes": {
                    "workspace": "hermes",
                    "peerName": "kaki",
                    "aiPeer": "personal-assistant",
                }
            },
        }

    def validate(self) -> list[str]:
        return MODULE.validate(self.contract, self.registry, self.honcho)

    def test_source_contract_registry_and_effective_identity_are_consistent(
        self,
    ) -> None:
        self.assertEqual(self.validate(), [])

    def test_rejects_effective_identity_drift_without_printing_unrelated_values(
        self,
    ) -> None:
        self.honcho["hosts"]["hermes"]["workspace"] = "wrong"
        errors = self.validate()
        self.assertTrue(any("workspace drift" in error for error in errors))
        self.assertNotIn("must-not-appear", "\n".join(errors))

    def test_host_identity_overrides_top_level_fallback(self) -> None:
        self.assertEqual(
            MODULE.effective_honcho_identity(self.honcho, "hermes"),
            {
                "workspace": "hermes",
                "user_peer": "kaki",
                "ai_peer": "personal-assistant",
            },
        )

    def test_rejects_duplicate_control_plane_claims(self) -> None:
        watari = self.registry["nodes"]["watari"]
        watari["default_profile_claims"]["gateway_writer"] = True
        watari["default_profile_claims"]["scheduler_writer"] = True
        watari["default_profile_claims"]["control_plane_writer"] = True
        errors = self.validate()
        self.assertTrue(
            any("gateway_writer must have exactly one owner" in e for e in errors)
        )
        self.assertTrue(
            any("scheduler_writer must have exactly one owner" in e for e in errors)
        )
        self.assertTrue(
            any("control_plane_writer must have exactly one owner" in e for e in errors)
        )

    def test_rejects_registry_identity_drift(self) -> None:
        self.registry["profiles"]["default"]["cross_host_continuity"][
            "semantic_identity"
        ]["ai_peer"] = "host-specific-peer"
        self.assertTrue(any("registry semantic identity" in e for e in self.validate()))

    def test_rejects_node_capability_drift(self) -> None:
        self.registry["nodes"]["watari"]["default_profile_roles"].append(
            "always-on-gateway"
        )
        self.assertTrue(any("roles differ" in e for e in self.validate()))

    def test_contract_keeps_live_and_sensitive_state_host_local(self) -> None:
        required = {
            "state.db",
            "state.db-wal",
            "state.db-shm",
            "routing",
            "queues",
            "cron-runtime",
            "auth",
            ".env",
            "secrets",
            "logs",
            "caches",
        }
        self.assertTrue(required <= set(self.contract["host_local_state"]))
        self.assertEqual(
            self.contract["session_continuity"],
            {
                "mechanism": "existing-source-authoritative-archive",
                "implementation": "not-reimplemented-by-this-candidate",
                "sources": ["lawliet", "watari"],
            },
        )

    def test_archive_syncthing_peers_match_the_live_qualified_node_ids(self) -> None:
        repository_root = SOURCE_ROOT.parents[1]
        lawliet_config = (
            repository_root / "systems/nixos/lawliet/syncthing.nix"
        ).read_text()
        watari_config = (
            repository_root / "homes/darwin/watari/syncthing.nix"
        ).read_text()
        lawliet_id = self.contract["nodes"]["lawliet"]["syncthing_device_id"]
        watari_id = self.contract["nodes"]["watari"]["syncthing_device_id"]

        self.assertIn(f'id = "{lawliet_id}";', watari_config)
        self.assertIn(f'watariDeviceId = "{watari_id}";', lawliet_config)
        self.assertNotIn(
            'id = "5DKI3TB-RHCDNPG-KQFLPIA-NPQNV45-UEPFADB-RQKZBG4-RT6KU6K-P6BX3AP";',
            watari_config,
        )

    def test_missing_honcho_file_is_a_safe_validation_error(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            missing = Path(temp) / "honcho.json"
            errors = MODULE.validate_paths(
                SOURCE_ROOT / "default-continuity-contract-v1.json",
                SOURCE_ROOT / "profile-registry.json",
                missing,
            )
        self.assertEqual(errors, [f"missing or invalid Honcho config: {missing}"])

    def test_contract_mutation_is_detected(self) -> None:
        mutated = copy.deepcopy(self.contract)
        mutated["nodes"]["watari"]["scheduler_writer"] = True
        errors = MODULE.validate(mutated, self.registry, self.honcho)
        self.assertTrue(any("contract scheduler_writer" in e for e in errors))


if __name__ == "__main__":
    unittest.main()
