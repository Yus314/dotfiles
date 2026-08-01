from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts/profile_summary_source_check.py"
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("profile_summary_source_check", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SummaryClassificationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.path = self.root / "2026-W29.md"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def classify(self, text: str | None, profile: str = "english") -> dict:
        if text is not None:
            self.path.write_text(text)
        return MODULE.classify_summary(
            self.path,
            expected_profile=profile,
            expected_week="2026-W29",
        )

    def test_missing_is_not_ready(self) -> None:
        result = self.classify(None)
        self.assertEqual(result["state"], "missing")
        self.assertFalse(result["ready"])

    def test_bootstrap_marker_can_never_be_ready(self) -> None:
        result = self.classify(
            "<!-- hermes-bootstrap-weekly-summary -->\n"
            "# 2026-W29 English weekly summary\n"
            "Status: bootstrap compact learning summary\n"
            "Owner profile: `english`\n"
            "Generated: 2026-07-14\n"
        )
        self.assertEqual(result["state"], "bootstrap")
        self.assertFalse(result["ready"])

    def test_domain_owned_legacy_handoff_is_ready(self) -> None:
        result = self.classify(
            "# 2026-W29 economics weekly summary\n"
            "Status: domain-owned pilot handoff\n"
            "Owner profile: `economics`\n"
            "Generated: 2026-07-14\n",
            profile="economics",
        )
        self.assertEqual(result["state"], "domain-owned")
        self.assertTrue(result["ready"])

    def test_owner_mismatch_is_invalid(self) -> None:
        result = self.classify(
            "# 2026-W29 English weekly summary\n"
            "Status: domain-owned\n"
            "Owner profile: `default`\n"
            "Generated: 2026-07-14\n"
        )
        self.assertEqual(result["state"], "invalid")
        self.assertFalse(result["ready"])
        self.assertIn("owner", result["reason"])

    def test_wrong_week_is_stale(self) -> None:
        result = self.classify(
            "# 2026-W28 English weekly summary\n"
            "Status: domain-owned handoff\n"
            "Owner profile: `english`\n"
        )
        self.assertEqual(result["state"], "stale")
        self.assertFalse(result["ready"])

    def test_current_week_mentioned_only_in_body_does_not_make_stale_heading_ready(self) -> None:
        result = self.classify(
            "# 2026-W28 English weekly summary\n"
            "Status: domain-owned handoff\n"
            "Owner profile: `english`\n"
            "Compared with 2026-W29 planning.\n"
        )
        self.assertEqual(result["state"], "stale")
        self.assertFalse(result["ready"])

    def test_conflicting_frontmatter_and_heading_weeks_are_invalid(self) -> None:
        result = self.classify(
            "---\n"
            "schema_version: 1\n"
            "owner_profile: english\n"
            "status: domain-owned\n"
            "week: 2026-W29\n"
            "---\n"
            "# 2026-W28 English weekly summary\n"
        )
        self.assertEqual(result["state"], "invalid")
        self.assertFalse(result["ready"])


    def test_frontmatter_schema_is_supported(self) -> None:
        result = self.classify(
            "---\n"
            "schema_version: 1\n"
            "domain: english\n"
            "owner_profile: english\n"
            "status: domain-owned\n"
            "generated_at: 2026-07-16T20:00:00+09:00\n"
            "coverage_start: 2026-07-13\n"
            "coverage_end: 2026-07-19\n"
            "source_watermark: 2026-07-16\n"
            "---\n"
            "# 2026-W29 English weekly handoff\n"
        )
        self.assertEqual(result["state"], "domain-owned")
        self.assertTrue(result["ready"])
        self.assertEqual(result["schema_version"], "1")

    def test_weekly_summary_family_is_validated(self) -> None:
        result = self.classify(
            "---\n"
            "schema_family: weekly_summary\n"
            "schema_version: 1\n"
            "owner_profile: english\n"
            "status: domain-owned\n"
            "generated_at: 2026-07-16T20:00:00+09:00\n"
            "coverage_start: 2026-07-13\n"
            "coverage_end: 2026-07-19\n"
            "source_watermark: review:2026-W29\n"
            "---\n"
            "# 2026-W29 English weekly summary\n"
        )
        self.assertEqual(result["state"], "domain-owned")
        self.assertTrue(result["ready"])

    def test_weekly_summary_family_rejects_invalid_coverage(self) -> None:
        result = self.classify(
            "---\n"
            "schema_family: weekly_summary\n"
            "schema_version: 1\n"
            "owner_profile: english\n"
            "status: domain-owned\n"
            "generated_at: 2026-07-16T20:00:00+09:00\n"
            "coverage_start: 2026-07-14\n"
            "coverage_end: 2026-07-19\n"
            "source_watermark: review:2026-W29\n"
            "---\n"
            "# 2026-W29 English weekly summary\n"
        )
        self.assertEqual(result["state"], "invalid")
        self.assertFalse(result["ready"])
        self.assertIn("week_not_covered", result["reason"])

    def test_handoff_family_cannot_masquerade_as_weekly_summary(self) -> None:
        result = self.classify(
            "---\n"
            "schema_family: cross_profile_handoff\n"
            "schema_version: 2\n"
            "owner_profile: english\n"
            "status: domain-owned\n"
            "generated_at: 2026-07-16T20:00:00+09:00\n"
            "coverage_start: 2026-07-13\n"
            "coverage_end: 2026-07-19\n"
            "source_watermark: review:2026-W29\n"
            "---\n"
            "# 2026-W29 English weekly summary\n"
        )
        self.assertEqual(result["state"], "invalid")
        self.assertIn("schema_family_invalid", result["reason"])

    def test_present_unreviewed_file_is_not_ready(self) -> None:
        result = self.classify(
            "# 2026-W29 English notes\nOwner profile: `english`\n"
        )
        self.assertEqual(result["state"], "needs-owner-review")
        self.assertFalse(result["ready"])


class SummaryPolicyTests(unittest.TestCase):
    def test_source_health_only_cannot_become_domain_ready(self) -> None:
        rows = [
            {
                "domain": "Finance",
                "profile": "finance",
                "path": f"~/ledger/personal/reports/weekly/{MODULE.WEEK}.md",
                "state": "domain-owned",
                "ready": True,
                "status": "Ready: owner-attested domain summary.",
            }
        ]
        policies = {
            "finance": {
                "summary_policy": "source-health-only",
                "summary_policy_reason": "",
                "summary_path": "~/ledger/personal/reports/weekly/{week}.md",
            }
        }
        [row] = MODULE.apply_summary_policies(rows, policies)
        self.assertEqual(row["state"], "policy-excluded")
        self.assertFalse(row["ready"])

    def test_blocked_policy_overrides_file_state(self) -> None:
        rows = [
            {
                "domain": "Health",
                "profile": "health",
                "path": f"~/org/health/google-health/weekly/{MODULE.WEEK}.md",
                "state": "domain-owned",
                "ready": True,
                "status": "Ready: owner-attested domain summary.",
            }
        ]
        policies = {
            "health": {
                "summary_policy": "blocked",
                "summary_policy_reason": "OAuth reauthorization required",
                "summary_path": "~/org/health/google-health/weekly/{week}.md",
            }
        }
        [row] = MODULE.apply_summary_policies(rows, policies)
        self.assertEqual(row["state"], "blocked")
        self.assertFalse(row["ready"])

    def test_missing_registry_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            missing = Path(temporary) / "missing.json"
            with self.assertRaises(MODULE.SummaryPolicyError):
                MODULE.load_summary_policies(missing)

    def test_none_policy_rejects_a_summary_path(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            registry = Path(temporary) / "registry.json"
            registry.write_text(
                json.dumps(
                    {
                        "schema_version": 2,
                        "profiles": {
                            "default": {
                                "summary_policy": "none",
                                "summary_path": "~/summary/{week}.md",
                            }
                        },
                    }
                )
            )
            with self.assertRaises(MODULE.SummaryPolicyError):
                MODULE.load_summary_policies(registry)


class NotificationTests(unittest.TestCase):
    def test_semantic_snapshot_ignores_file_and_content_churn(self) -> None:
        before = [
            {
                "domain": "Calendar",
                "profile": "default",
                "path": "~/org/calendar.org",
                "exists": True,
                "size": 100,
                "state": "source-present",
                "ready": True,
                "reason": "source-present",
                "sha256": "old",
            },
            {
                "domain": "English learning",
                "profile": "english",
                "path": "~/english.md",
                "exists": True,
                "size": 10,
                "state": "domain-owned",
                "ready": True,
                "reason": "owner-attested",
                "sha256": "old-summary",
            },
        ]
        after = [
            {**before[0], "size": 200, "sha256": "new"},
            {**before[1], "size": 20, "sha256": "new-summary"},
        ]
        self.assertEqual(
            MODULE.semantic_snapshot(before), MODULE.semantic_snapshot(after)
        )
        self.assertEqual(MODULE.changed_semantic_rows(before, after), [])

    def test_path_churn_does_not_change_readiness(self) -> None:
        before = [
            {
                "domain": "English learning",
                "profile": "english",
                "path": "~/old.md",
                "state": "missing",
                "ready": False,
                "reason": "file missing",
            }
        ]
        after = [{**before[0], "path": "~/new.md"}]
        self.assertEqual(MODULE.changed_semantic_rows(before, after), [])

    def test_malformed_stored_rows_become_silent_baseline(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            state_file = Path(temporary) / "state.json"
            state_file.write_text('{"rows": ["not-a-row"]}')
            self.assertIsNone(MODULE.load_previous_rows(state_file))

    def test_new_week_baseline_is_silent(self) -> None:
        rows = [
            {
                "domain": "English learning",
                "profile": "english",
                "path": "~/english.md",
                "state": "missing",
                "ready": False,
                "reason": "file missing",
            }
        ]
        self.assertEqual(MODULE.notification_lines(None, rows), [])

    def test_notification_lists_only_semantically_changed_rows(self) -> None:
        before = [
            {
                "domain": "Calendar",
                "profile": "default",
                "path": "~/org/calendar.org",
                "state": "source-present",
                "ready": True,
                "reason": "source-present",
            },
            {
                "domain": "English learning",
                "profile": "english",
                "path": "~/english.md",
                "summary_policy": "active-weekly",
                "state": "missing",
                "ready": False,
                "reason": "file missing",
            },
        ]
        after = [
            before[0],
            {
                **before[1],
                "state": "domain-owned",
                "ready": True,
                "reason": "owner-attested",
            },
        ]
        lines = MODULE.notification_lines(before, after)
        self.assertIn("Semantic readiness changed", lines[0])
        self.assertTrue(any("English learning (english): missing -> domain-owned" in line for line in lines))
        self.assertFalse(any("Calendar" in line for line in lines))
    def test_on_demand_transition_does_not_notify(self) -> None:
        before = [
            {
                "domain": "Career",
                "profile": "career",
                "path": "~/career.md",
                "summary_policy": "on-demand",
                "state": "missing",
                "ready": False,
                "reason": "file missing",
            }
        ]
        after = [
            {**before[0], "state": "domain-owned", "ready": True}
        ]
        self.assertEqual(MODULE.notification_lines(before, after), [])


class RenderTests(unittest.TestCase):
    def test_render_distinguishes_file_presence_from_readiness(self) -> None:
        rows = [
            {
                "domain": "Economics",
                "profile": "economics",
                "path": "~/economics.md",
                "exists": True,
                "size": 10,
                "state": "domain-owned",
                "ready": True,
                "status": "Ready: domain-owned summary.",
                "reason": "owner-attested",
                "sha256": "a",
            },
            {
                "domain": "Career",
                "profile": "career",
                "path": "~/career.md",
                "exists": True,
                "size": 10,
                "state": "bootstrap",
                "ready": False,
                "status": "Bootstrap only: not reviewed.",
                "reason": "bootstrap marker",
                "sha256": "b",
            },
        ]
        rendered = MODULE.render(rows)
        self.assertIn("domain-owned across all policies: 1", rendered)
        self.assertIn("not ready across all policies: 1", rendered)
        self.assertIn("Bootstrap only", rendered)
        self.assertNotIn("Career | career | `~/career.md` | Available", rendered)

    def test_render_counts_only_active_weekly_domains(self) -> None:
        rows = [
            {
                "domain": "English learning",
                "profile": "english",
                "path": "~/english.md",
                "summary_policy": "active-weekly",
                "exists": False,
                "size": 0,
                "state": "missing",
                "ready": False,
                "status": "Missing",
                "reason": "file missing",
                "sha256": "",
            },
            {
                "domain": "Career",
                "profile": "career",
                "path": "~/career.md",
                "summary_policy": "on-demand",
                "exists": False,
                "size": 0,
                "state": "missing",
                "ready": False,
                "status": "Missing",
                "reason": "file missing",
                "sha256": "",
            },
            {
                "domain": "Health",
                "profile": "health",
                "path": "~/health.md",
                "summary_policy": "blocked",
                "summary_policy_reason": "OAuth reauthorization required",
                "exists": False,
                "size": 0,
                "state": "missing",
                "ready": False,
                "status": "Missing",
                "reason": "file missing",
                "sha256": "",
            },
        ]
        rendered = MODULE.render(rows)
        self.assertIn("weekly-required: 0/1", rendered)
        self.assertIn("blocked: 1", rendered)
        self.assertIn("OAuth reauthorization required", rendered)


if __name__ == "__main__":
    unittest.main()
