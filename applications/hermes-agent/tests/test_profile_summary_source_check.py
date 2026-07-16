from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts/profile_summary_source_check.py"
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

    def test_present_unreviewed_file_is_not_ready(self) -> None:
        result = self.classify(
            "# 2026-W29 English notes\nOwner profile: `english`\n"
        )
        self.assertEqual(result["state"], "needs-owner-review")
        self.assertFalse(result["ready"])


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
        self.assertIn("domain-owned: 1", rendered)
        self.assertIn("not ready: 1", rendered)
        self.assertIn("Bootstrap only", rendered)
        self.assertNotIn("Career | career | `~/career.md` | Available", rendered)


if __name__ == "__main__":
    unittest.main()
