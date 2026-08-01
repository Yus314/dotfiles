from __future__ import annotations

import datetime as dt
import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts/profile_exchange_schema.py"
SPEC = importlib.util.spec_from_file_location("profile_exchange_schema", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class WeeklySummarySchemaTests(unittest.TestCase):
    def valid(self) -> dict:
        return {
            "schema_family": "weekly_summary",
            "schema_version": 1,
            "owner_profile": "english",
            "generated_at": "2026-07-16T20:00:00+09:00",
            "coverage_start": "2026-07-13",
            "coverage_end": "2026-07-19",
            "source_watermark": "review:2026-W29",
            "status": "domain-owned",
        }

    def validate(self, metadata: dict) -> list[str]:
        return MODULE.validate_weekly_summary(
            metadata,
            expected_owner="english",
            expected_week="2026-W29",
        )

    def test_valid_weekly_summary(self) -> None:
        self.assertEqual(self.validate(self.valid()), [])

    def test_rejects_owner_and_coverage_mismatch(self) -> None:
        metadata = self.valid()
        metadata["owner_profile"] = "default"
        metadata["coverage_start"] = "2026-07-14"
        metadata["coverage_end"] = "2026-07-12"
        errors = self.validate(metadata)
        self.assertIn("owner_mismatch", errors)
        self.assertIn("invalid_coverage_order", errors)
        self.assertIn("week_not_covered", errors)

    def test_rejects_timezone_less_generation_time(self) -> None:
        metadata = self.valid()
        metadata["generated_at"] = "2026-07-16T20:00:00"
        self.assertIn("generated_at_requires_timezone", self.validate(metadata))


class HandoffSchemaTests(unittest.TestCase):
    NOW = dt.datetime(2026, 8, 1, 0, 0, tzinfo=dt.timezone.utc)

    def valid(self) -> dict:
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

    def validate(self, metadata: dict, **overrides) -> list[str]:
        kwargs = {
            "expected_target": "default",
            "now": self.NOW,
            "registered_profiles": {"default", "food", "health"},
            "allowed_purposes": {
                "stable-preference-promotion",
                "compact-status",
                "task-result",
                "review-request",
                "consultation-response",
            },
            "allowed_sensitivity": {"ordinary"},
            "seen_ids": set(),
        }
        kwargs.update(overrides)
        return MODULE.validate_handoff(metadata, **kwargs)

    def test_valid_handoff(self) -> None:
        self.assertEqual(self.validate(self.valid()), [])

    def test_accepts_timezone_aware_datetime_objects_from_yaml(self) -> None:
        metadata = self.valid()
        metadata["generated_at"] = dt.datetime(
            2026, 8, 1, 8, 0, tzinfo=dt.timezone(dt.timedelta(hours=9))
        )
        metadata["valid_until"] = dt.datetime(
            2026, 8, 15, 0, 0, tzinfo=dt.timezone(dt.timedelta(hours=9))
        )
        self.assertEqual(self.validate(metadata), [])

    def test_valid_consultation_request(self) -> None:
        metadata = self.valid()
        metadata.update(
            {
                "purpose": "review-request",
                "requested_fields": ["status", "confidence"],
                "response_deadline": "2026-08-02T00:00:00+00:00",
                "in_reply_to": None,
                "hop_count": 0,
                "max_hops": 1,
            }
        )
        self.assertEqual(self.validate(metadata), [])

    def test_valid_consultation_response(self) -> None:
        metadata = self.valid()
        metadata.update(
            {
                "purpose": "consultation-response",
                "in_reply_to": "default:2026-08-01:request",
                "returned_fields": ["status", "confidence"],
                "hop_count": 1,
                "max_hops": 1,
            }
        )
        self.assertEqual(self.validate(metadata), [])

    def test_rejects_invalid_consultation_semantics(self) -> None:
        request = self.valid()
        request["purpose"] = "review-request"
        errors = self.validate(request)
        self.assertIn("consultation_requested_fields_missing", errors)
        self.assertIn("consultation_response_deadline_missing", errors)
        self.assertIn("consultation_hop_fields_missing", errors)

        response = self.valid()
        response.update(
            {
                "purpose": "consultation-response",
                "in_reply_to": response["handoff_id"],
                "returned_fields": [],
                "hop_count": 2,
                "max_hops": 1,
            }
        )
        errors = self.validate(response)
        self.assertIn("consultation_response_self_reference", errors)
        self.assertIn("consultation_returned_fields_invalid", errors)
        self.assertIn("consultation_hop_limit_exceeded", errors)

    def test_rejects_missing_and_unknown_fields(self) -> None:
        metadata = self.valid()
        del metadata["purpose"]
        metadata["raw_rows"] = ["secret"]
        errors = self.validate(metadata)
        self.assertIn("missing_field:purpose", errors)
        self.assertIn("unknown_field:raw_rows", errors)

    def test_rejects_wrong_recipient_and_unknown_profiles(self) -> None:
        metadata = self.valid()
        metadata["source_profile"] = "missing"
        metadata["target_profiles"] = ["health", "missing"]
        errors = self.validate(metadata)
        self.assertIn("source_profile_unknown", errors)
        self.assertIn("target_profile_missing:default", errors)
        self.assertIn("target_profile_unknown:missing", errors)

    def test_rejects_expired_and_timezone_less_timestamps(self) -> None:
        metadata = self.valid()
        metadata["generated_at"] = "2026-07-01T00:00:00"
        metadata["valid_until"] = "2026-07-31T00:00:00+00:00"
        errors = self.validate(metadata)
        self.assertIn("generated_at_requires_timezone", errors)
        self.assertIn("handoff_expired", errors)

    def test_rejects_raw_data_and_path_source_reference(self) -> None:
        metadata = self.valid()
        metadata["raw_data_included"] = True
        metadata["source_refs"] = [
            {"type": "opaque-handle", "value": "~/org/food/raw.md"}
        ]
        errors = self.validate(metadata)
        self.assertIn("raw_data_forbidden", errors)
        self.assertIn("invalid_source_ref:0", errors)

    def test_rejects_disallowed_purpose_sensitivity_and_retention(self) -> None:
        metadata = self.valid()
        metadata["purpose"] = "copy-everything"
        metadata["sensitivity"] = "restricted"
        metadata["retention_class"] = "forever"
        errors = self.validate(metadata)
        self.assertIn("purpose_not_allowed", errors)
        self.assertIn("sensitivity_not_allowed", errors)
        self.assertIn("retention_class_invalid", errors)

    def test_rejects_replay_and_self_supersession(self) -> None:
        metadata = self.valid()
        metadata["supersedes"] = metadata["handoff_id"]
        errors = self.validate(metadata, seen_ids={metadata["handoff_id"]})
        self.assertIn("handoff_replayed", errors)
        self.assertIn("handoff_supersedes_self", errors)


if __name__ == "__main__":
    unittest.main()
