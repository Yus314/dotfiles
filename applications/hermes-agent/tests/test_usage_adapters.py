from __future__ import annotations

import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    "default": "~/.hermes/state.db",
    "career": "~/.hermes/profiles/career/state.db",
    "english": "~/.hermes/profiles/english/state.db",
    "indiedev": "~/.hermes/profiles/indiedev/state.db",
    "researcheval": "~/.hermes/profiles/researcheval/state.db",
}


class UsageAdapterTests(unittest.TestCase):
    def test_adapters_are_profile_local_and_route_exact_database(self) -> None:
        for profile, db_path in EXPECTED.items():
            path = ROOT / "profile-skills" / profile / "hermes-usage-analysis-local" / "SKILL.md"
            text = path.read_text(encoding="utf-8")
            _, frontmatter, _ = text.split("---", 2)
            metadata = yaml.safe_load(frontmatter)
            self.assertEqual(metadata["name"], "hermes-usage-analysis-local")
            self.assertIn(f"`--profile {profile}`", text)
            self.assertIn(f"`{db_path}`", text)
            self.assertIn("does not implicitly analyze this profile", text)

    def test_non_consumers_have_no_adapter_source(self) -> None:
        for profile in {"economics", "finance", "food", "health", "math"}:
            self.assertFalse((ROOT / "profile-skills" / profile).exists())


if __name__ == "__main__":
    unittest.main()
