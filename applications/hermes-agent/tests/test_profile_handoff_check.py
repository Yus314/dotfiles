from __future__ import annotations

import datetime as dt
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml


SCRIPT = Path(__file__).parents[1] / "scripts/profile_handoff_check.py"
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("profile_handoff_check", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ProfileHandoffCheckTests(unittest.TestCase):
    NOW = dt.datetime(2026, 8, 1, 0, 0, tzinfo=dt.timezone.utc)

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.registry = self.root / "profile-registry.json"
        self.handoff = self.root / "handoff.md"
        self.registry.write_text(
            json.dumps(
                {
                    "schema_version": 2,
                    "profiles": {"default": {}, "food": {}, "health": {}},
                    "information_exchange": {
                        "handoff": {
                            "schema_family": "cross_profile_handoff",
                            "schema_version": 2,
                            "allowed_purposes": [
                                "stable-preference-promotion",
                                "compact-status",
                            ],
                            "retention_classes": [
                                "transient",
                                "promotable",
                                "durable",
                            ],
                            "destination_sensitivity": {
                                "default": ["ordinary"],
                                "health": ["ordinary", "sensitive"],
                            },
                        }
                    },
                }
            )
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def metadata(self) -> dict:
        return {
            "schema_family": "cross_profile_handoff",
            "schema_version": 2,
            "handoff_id": "food:2026-08-01:stable-preference",
            "source_profile": "food",
            "target_profiles": ["default"],
            "purpose": "stable-preference-promotion",
            "generated_at": "2026-08-01T08:00:00+09:00",
            "valid_until": "2026-08-15T00:00:00+09:00",
            "scope": "stable-preference-only",
            "status": "ready",
            "source_refs": [
                {
                    "type": "opaque-handle",
                    "value": "food-preference-review:2026-08-01",
                }
            ],
            "source_health": "healthy",
            "sensitivity": "ordinary",
            "raw_data_included": False,
            "retention_class": "promotable",
            "supersedes": None,
            "assumptions": [],
            "uncertainties": [],
        }

    def write_handoff(self, metadata: dict, body: str = "PRIVATE BODY") -> None:
        self.handoff.write_text(
            "---\n"
            + yaml.safe_dump(metadata, sort_keys=False)
            + "---\n"
            + body
            + "\n"
        )

    def test_accepts_valid_handoff_without_returning_body(self) -> None:
        self.write_handoff(self.metadata())
        result = MODULE.check_handoff(
            self.handoff,
            target="default",
            registry_path=self.registry,
            now=self.NOW,
        )
        self.assertTrue(result["valid"])
        self.assertEqual(result["handoff_id"], self.metadata()["handoff_id"])
        self.assertNotIn("body", result)
        self.assertNotIn("PRIVATE BODY", json.dumps(result))

    def test_rejects_raw_data_without_echoing_body(self) -> None:
        metadata = self.metadata()
        metadata["raw_data_included"] = True
        self.write_handoff(metadata, body="DO-NOT-ECHO-SECRET")
        result = MODULE.check_handoff(
            self.handoff,
            target="default",
            registry_path=self.registry,
            now=self.NOW,
        )
        self.assertFalse(result["valid"])
        self.assertIn("raw_data_forbidden", result["reason_codes"])
        self.assertNotIn("DO-NOT-ECHO-SECRET", json.dumps(result))

    def test_rejects_seen_handoff_id(self) -> None:
        metadata = self.metadata()
        self.write_handoff(metadata)
        seen = self.root / "seen.json"
        seen.write_text(json.dumps([metadata["handoff_id"]]))
        result = MODULE.check_handoff(
            self.handoff,
            target="default",
            registry_path=self.registry,
            now=self.NOW,
            seen_ids_path=seen,
        )
        self.assertFalse(result["valid"])
        self.assertIn("handoff_replayed", result["reason_codes"])

    def test_cli_accepts_yaml_timestamp_objects(self) -> None:
        metadata = self.metadata()
        metadata["generated_at"] = dt.datetime(
            2026, 8, 1, 8, 0, tzinfo=dt.timezone(dt.timedelta(hours=9))
        )
        metadata["valid_until"] = dt.datetime(
            2026, 8, 15, 0, 0, tzinfo=dt.timezone(dt.timedelta(hours=9))
        )
        self.write_handoff(metadata)
        completed = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                str(self.handoff),
                "--target",
                "default",
                "--registry",
                str(self.registry),
                "--now",
                self.NOW.isoformat(),
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        payload = json.loads(completed.stdout)
        self.assertTrue(payload["valid"])
        self.assertEqual(payload["valid_until"], "2026-08-15T00:00:00+09:00")

    def test_cli_exit_one_emits_compact_json_not_body(self) -> None:
        metadata = self.metadata()
        metadata["target_profiles"] = ["health"]
        self.write_handoff(metadata, body="DO-NOT-ECHO-SECRET")
        completed = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                str(self.handoff),
                "--target",
                "default",
                "--registry",
                str(self.registry),
                "--now",
                self.NOW.isoformat(),
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 1)
        payload = json.loads(completed.stdout)
        self.assertFalse(payload["valid"])
        self.assertNotIn("DO-NOT-ECHO-SECRET", completed.stdout)
        self.assertEqual(completed.stderr, "")


if __name__ == "__main__":
    unittest.main()
