from __future__ import annotations

import datetime as dt
import importlib.util
import json
import stat
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "profile_consult.py"
SPEC = importlib.util.spec_from_file_location("profile_consult", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ProfileConsultTests(unittest.TestCase):
    NOW = dt.datetime(2026, 8, 1, 2, 30, tzinfo=dt.timezone.utc)

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "consult"
        self.registry = Path(self.temp.name) / "registry.json"
        payload = {
            "schema_version": 2,
            "profiles": {name: {} for name in ["default", "finance", "career", "economics", "math"]},
            "information_exchange": {
                "handoff": {
                    "schema_family": "cross_profile_handoff",
                    "schema_version": 2,
                    "allowed_purposes": [
                        "compact-status",
                        "review-request",
                        "consultation-response",
                    ],
                    "retention_classes": ["transient", "promotable", "durable"],
                    "destination_sensitivity": {
                        "default": ["ordinary"],
                        "finance": ["ordinary", "sensitive", "restricted"],
                        "career": ["ordinary"],
                        "economics": ["ordinary"],
                        "math": ["ordinary"],
                    },
                },
                "consultation": {
                    "schema_version": 1,
                    "max_hops": 1,
                    "routes": [
                        {
                            "source": "default",
                            "target": "finance",
                            "max_ttl_hours": 24,
                            "allowed_requested_fields": [
                                "status",
                                "constraints",
                                "confidence",
                                "as_of",
                            ],
                        },
                        {
                            "source": "default",
                            "target": "career",
                            "max_ttl_hours": 24,
                            "allowed_requested_fields": ["availability_status", "confidence", "as_of"],
                        },
                        {
                            "source": "default",
                            "target": "economics",
                            "max_ttl_hours": 72,
                            "allowed_requested_fields": ["status", "confidence", "updated_at"],
                        },
                        {
                            "source": "math",
                            "target": "economics",
                            "max_ttl_hours": 72,
                            "allowed_requested_fields": ["status", "confidence", "updated_at"],
                        },
                    ],
                },
            },
        }
        self.registry.write_text(json.dumps(payload), encoding="utf-8")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_request_response_round_trip_and_compact_status(self) -> None:
        request = MODULE.create_request(
            root=self.root,
            registry_path=self.registry,
            source="default",
            target="finance",
            scope="housing-decision-support",
            requested_fields=["status", "confidence"],
            now=self.NOW,
            ttl_hours=12,
            handoff_id="default:2026-08-01:finance-status",
        )
        request_path = Path(request["path"])
        self.assertTrue(request_path.is_file())
        self.assertEqual(stat.S_IMODE(request_path.stat().st_mode), 0o600)
        self.assertEqual(request["purpose"], "review-request")

        response = MODULE.create_response(
            root=self.root,
            registry_path=self.registry,
            request_path=request_path,
            source="finance",
            response_fields={"status": "available", "confidence": "medium"},
            now=self.NOW + dt.timedelta(minutes=5),
            handoff_id="finance:2026-08-01:finance-status-response",
        )
        response_path = Path(response["path"])
        self.assertTrue(response_path.is_file())
        self.assertEqual(stat.S_IMODE(response_path.stat().st_mode), 0o600)
        self.assertEqual(response["in_reply_to"], request["handoff_id"])

        status_rows = MODULE.consultation_status(
            root=self.root,
            registry_path=self.registry,
            now=self.NOW + dt.timedelta(minutes=6),
        )
        self.assertEqual(
            status_rows,
            [
                {
                    "request_id": request["handoff_id"],
                    "source": "default",
                    "target": "finance",
                    "state": "answered",
                    "response_id": response["handoff_id"],
                    "response_deadline": "2026-08-01T14:30:00+00:00",
                }
            ],
        )

    def test_rejects_unapproved_route_and_fields(self) -> None:
        with self.assertRaisesRegex(MODULE.ConsultError, "consultation_route_not_allowed"):
            MODULE.create_request(
                root=self.root,
                registry_path=self.registry,
                source="finance",
                target="default",
                scope="reverse",
                requested_fields=["status"],
                now=self.NOW,
                ttl_hours=1,
            )
        with self.assertRaisesRegex(MODULE.ConsultError, "requested_field_not_allowed"):
            MODULE.create_request(
                root=self.root,
                registry_path=self.registry,
                source="default",
                target="finance",
                scope="too-broad",
                requested_fields=["balance"],
                now=self.NOW,
                ttl_hours=1,
            )

    def test_rejects_ttl_above_route_limit(self) -> None:
        with self.assertRaisesRegex(MODULE.ConsultError, "ttl_exceeds_route_limit"):
            MODULE.create_request(
                root=self.root,
                registry_path=self.registry,
                source="default",
                target="finance",
                scope="stale-risk",
                requested_fields=["status"],
                now=self.NOW,
                ttl_hours=25,
            )

    def test_response_must_match_target_and_requested_fields(self) -> None:
        request = MODULE.create_request(
            root=self.root,
            registry_path=self.registry,
            source="default",
            target="finance",
            scope="housing-decision-support",
            requested_fields=["status"],
            now=self.NOW,
            ttl_hours=12,
        )
        request_path = Path(request["path"])
        with self.assertRaisesRegex(MODULE.ConsultError, "response_source_mismatch"):
            MODULE.create_response(
                root=self.root,
                registry_path=self.registry,
                request_path=request_path,
                source="career",
                response_fields={"status": "unknown"},
                now=self.NOW + dt.timedelta(minutes=1),
            )
        with self.assertRaisesRegex(MODULE.ConsultError, "returned_field_not_requested"):
            MODULE.create_response(
                root=self.root,
                registry_path=self.registry,
                request_path=request_path,
                source="finance",
                response_fields={"confidence": "low"},
                now=self.NOW + dt.timedelta(minutes=1),
            )

    def test_duplicate_id_fails_without_overwrite(self) -> None:
        kwargs = dict(
            root=self.root,
            registry_path=self.registry,
            source="default",
            target="finance",
            scope="housing",
            requested_fields=["status"],
            now=self.NOW,
            ttl_hours=1,
            handoff_id="default:2026-08-01:duplicate",
        )
        first = MODULE.create_request(**kwargs)
        original = Path(first["path"]).read_bytes()
        with self.assertRaisesRegex(MODULE.ConsultError, "artifact_exists"):
            MODULE.create_request(**kwargs)
        self.assertEqual(Path(first["path"]).read_bytes(), original)

    def test_status_rejects_forged_response_pair(self) -> None:
        request = MODULE.create_request(
            root=self.root,
            registry_path=self.registry,
            source="default",
            target="finance",
            scope="housing",
            requested_fields=["status"],
            now=self.NOW,
            ttl_hours=1,
        )
        response = MODULE.create_response(
            root=self.root,
            registry_path=self.registry,
            request_path=Path(request["path"]),
            source="finance",
            response_fields={"status": "unknown"},
            now=self.NOW + dt.timedelta(minutes=1),
        )
        response_path = Path(response["path"])
        metadata = MODULE._load_frontmatter(response_path)
        metadata["returned_fields"] = ["balance"]
        response_path.write_bytes(MODULE._render(metadata, "# forged metadata-only fixture"))
        rows = MODULE.consultation_status(
            root=self.root,
            registry_path=self.registry,
            now=self.NOW + dt.timedelta(minutes=2),
        )
        self.assertEqual(rows[0]["state"], "invalid-response")
        self.assertIsNone(rows[0]["response_id"])


if __name__ == "__main__":
    unittest.main()
