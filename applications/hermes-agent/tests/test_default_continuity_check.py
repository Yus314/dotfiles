from __future__ import annotations

import copy
import importlib.util
import json
import subprocess
import sys
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

    def test_contract_separates_session_transport_reconciliation_hold(self) -> None:
        expected = {
            "mechanism": "existing-source-authoritative-archive",
            "implementation": "not-reimplemented-by-this-candidate",
            "sources": ["lawliet", "watari"],
            "transport_readiness": "blocked-pending-separate-device-reconciliation",
        }
        self.assertEqual(self.contract["session_continuity"], expected)
        self.assertEqual(
            self.registry["profiles"]["default"]["cross_host_continuity"][
                "session_continuity"
            ],
            expected,
        )
        self.assertFalse(
            any(
                "syncthing_device_id" in node
                for node in self.contract["nodes"].values()
            )
        )

    def test_host_identity_overrides_top_level_fallback(self) -> None:
        self.assertEqual(
            MODULE.effective_honcho_identity(self.honcho, "hermes"),
            {
                "workspace": "hermes",
                "user_peer": "kaki",
                "ai_peer": "personal-assistant",
            },
        )

    def test_nested_secret_in_identity_is_never_returned(self) -> None:
        secret = "NESTED-SECRET-MUST-NOT-LEAK"
        self.honcho["hosts"]["hermes"]["workspace"] = {"token": secret}
        errors = self.validate()
        self.assertEqual(errors, ["HONCHO_IDENTITY_DRIFT"])
        self.assertNotIn(secret, "\n".join(errors))

    def test_wrong_type_in_host_local_state_is_structured(self) -> None:
        self.contract["host_local_state"] = [{"secret": "DO-NOT-ECHO"}]
        errors = self.validate()
        self.assertIn("CONTRACT_HOST_LOCAL_STATE_INVALID", errors)
        self.assertNotIn("DO-NOT-ECHO", "\n".join(errors))

    def test_unknown_contract_node_writer_claim_is_rejected(self) -> None:
        self.contract["nodes"]["watari"]["future_writer"] = True
        self.assertIn("CONTRACT_NODES_INVALID", self.validate())

    def test_boolean_schema_version_is_rejected(self) -> None:
        self.contract["schema_version"] = True
        self.assertIn("CONTRACT_HEADER_INVALID", self.validate())

    def test_unknown_registry_writer_claim_is_rejected(self) -> None:
        self.registry["nodes"]["watari"]["default_profile_claims"]["future_writer"] = (
            True
        )
        self.assertIn("REGISTRY_WRITER_CLAIMS_INVALID", self.validate())

    def test_duplicate_control_plane_claims_are_rejected(self) -> None:
        claims = self.registry["nodes"]["watari"]["default_profile_claims"]
        for claim in MODULE.WRITER_CLAIMS:
            claims[claim] = True
        self.assertIn("REGISTRY_WRITER_OWNERSHIP_INVALID", self.validate())

    def test_registry_control_plane_drift_is_rejected(self) -> None:
        self.registry["control_plane"] = "other"
        self.assertIn("REGISTRY_CONTROL_PLANE_DRIFT", self.validate())

    def test_default_memory_workspace_drift_is_rejected(self) -> None:
        self.registry["profiles"]["default"]["memory_workspace"] = "other"
        self.assertIn("REGISTRY_DEFAULT_WORKSPACE_DRIFT", self.validate())

    def test_general_shared_workspace_drift_is_rejected(self) -> None:
        self.registry["information_exchange"]["semantic_memory"][
            "general_shared_workspace"
        ] = "other"
        self.assertIn("REGISTRY_SHARED_WORKSPACE_DRIFT", self.validate())

    def test_session_mechanism_drift_is_rejected(self) -> None:
        self.contract["session_continuity"]["mechanism"] = "other"
        self.assertIn("CONTRACT_SESSION_POLICY_INVALID", self.validate())

    def test_session_implementation_drift_is_rejected(self) -> None:
        self.contract["session_continuity"]["implementation"] = "live"
        self.assertIn("CONTRACT_SESSION_POLICY_INVALID", self.validate())

    def test_session_source_roster_drift_is_rejected(self) -> None:
        self.contract["session_continuity"]["sources"] = ["lawliet"]
        self.assertIn("CONTRACT_SESSION_POLICY_INVALID", self.validate())

    def test_registry_session_policy_drift_is_rejected(self) -> None:
        self.registry["profiles"]["default"]["cross_host_continuity"][
            "session_continuity"
        ]["sources"] = ["watari", "lawliet"]
        self.assertIn("REGISTRY_SESSION_POLICY_DRIFT", self.validate())

    def test_node_roster_drift_is_rejected(self) -> None:
        self.contract["nodes"]["future"] = copy.deepcopy(
            self.contract["nodes"]["watari"]
        )
        self.assertIn("CONTRACT_NODES_INVALID", self.validate())

    def test_invalid_utf8_has_fixed_load_refusal(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            invalid = Path(temp) / "contains-secret-name.json"
            invalid.write_bytes(b"\xffSECRET")
            errors = MODULE.validate_paths(
                invalid,
                SOURCE_ROOT / "profile-registry.json",
                SOURCE_ROOT / "profile-configs/finance/honcho.json",
            )
        self.assertEqual(errors, ["CONTRACT_LOAD_REFUSED"])
        self.assertNotIn("secret", "\n".join(errors).lower())

    def test_duplicate_json_keys_have_fixed_load_refusal(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            duplicate = Path(temp) / "contract.json"
            duplicate.write_text('{"schema_version":1,"schema_version":2}')
            errors = MODULE.validate_paths(
                duplicate,
                SOURCE_ROOT / "profile-registry.json",
                SOURCE_ROOT / "profile-configs/finance/honcho.json",
            )
        self.assertEqual(errors, ["CONTRACT_LOAD_REFUSED"])

    def test_malformed_json_has_fixed_load_refusal(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            malformed = Path(temp) / "SECRET-contract.json"
            malformed.write_text('{"schema_version":')
            errors = MODULE.validate_paths(
                malformed,
                SOURCE_ROOT / "profile-registry.json",
                SOURCE_ROOT / "profile-configs/finance/honcho.json",
            )
        self.assertEqual(errors, ["CONTRACT_LOAD_REFUSED"])
        self.assertNotIn("SECRET", "\n".join(errors))

    def test_reason_envelope_is_bounded_and_contains_only_fixed_codes(self) -> None:
        hostile_contract = {f"secret-{index}": index for index in range(1000)}
        errors = MODULE.validate(hostile_contract, self.registry, self.honcho)
        self.assertLessEqual(len(errors), MODULE.MAX_REASONS)
        self.assertTrue(errors)
        self.assertTrue(all(error.isupper() and " " not in error for error in errors))
        self.assertNotIn("secret", "\n".join(errors).lower())

    def test_darwin_default_honcho_secret_is_narrow_and_declarative(self) -> None:
        module_text = (SOURCE_ROOT / "default.nix").read_text()
        darwin_block = module_text.split(
            "(lib.mkIf pkgs.stdenv.isDarwin {", maxsplit=1
        )[1].split("(lib.mkIf pkgs.stdenv.isLinux {", maxsplit=1)[0]
        self.assertIn('sops.secrets."hermes-default-honcho-env"', darwin_block)
        self.assertIn('key = "default_honcho_env";', darwin_block)
        self.assertIn(
            'path = "${config.home.homeDirectory}/.hermes/.env";', darwin_block
        )
        self.assertIn('mode = "0400";', darwin_block)
        self.assertNotIn('key = "env";', darwin_block)
        encrypted = (SOURCE_ROOT / "secrets.yaml").read_text()
        self.assertIn("default_honcho_env: ENC[", encrypted)
        self.assertNotIn("HONCHO_API_KEY", encrypted)

    def test_activation_gate_uses_store_command_and_deployed_inputs(self) -> None:
        module_text = (SOURCE_ROOT / "shared-workflows.nix").read_text()
        gate = module_text.split(
            "home.activation.hermesDefaultContinuityCheck =", maxsplit=1
        )[1]
        self.assertIn(
            "${defaultContinuityCheck}/bin/hermes-default-continuity-check", gate
        )
        self.assertIn(
            '"$HOME/.local/share/hermes/default-continuity-contract-v1.json"', gate
        )
        self.assertIn('"$HOME/.local/share/hermes/profile-registry.json"', gate)
        self.assertIn('"$HOME/.hermes/honcho.json"', gate)
        self.assertIn('"linkGeneration"', gate)

    def test_missing_honcho_file_has_fixed_load_refusal(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            missing = Path(temp) / "TOP-SECRET-honcho.json"
            errors = MODULE.validate_paths(
                SOURCE_ROOT / "default-continuity-contract-v1.json",
                SOURCE_ROOT / "profile-registry.json",
                missing,
            )
        self.assertEqual(errors, ["HONCHO_LOAD_REFUSED"])
        self.assertNotIn("TOP-SECRET", "\n".join(errors))

    def test_public_cli_refusal_is_fixed_and_non_secret(self) -> None:
        secret = "CLI-SECRET-MUST-NOT-LEAK"
        with tempfile.TemporaryDirectory() as temp:
            honcho = Path(temp) / f"{secret}.json"
            honcho.write_text(
                json.dumps(
                    {
                        "hosts": {
                            "hermes": {
                                "workspace": {"nested": secret},
                                "peerName": "kaki",
                                "aiPeer": "personal-assistant",
                            }
                        }
                    }
                )
            )
            completed = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--contract",
                    str(SOURCE_ROOT / "default-continuity-contract-v1.json"),
                    "--registry",
                    str(SOURCE_ROOT / "profile-registry.json"),
                    "--honcho",
                    str(honcho),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
        self.assertEqual(completed.returncode, 1)
        self.assertEqual(
            completed.stdout,
            "DEFAULT_CONTINUITY_INVALID\n- HONCHO_IDENTITY_DRIFT\n",
        )
        self.assertEqual(completed.stderr, "")
        self.assertNotIn(secret, completed.stdout + completed.stderr)


if __name__ == "__main__":
    unittest.main()
