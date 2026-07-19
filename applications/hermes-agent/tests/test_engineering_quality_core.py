from __future__ import annotations

import json
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "shared-skills/engineering/engineering-quality-core"


class EngineeringQualityCoreTests(unittest.TestCase):
    def test_package_is_a_small_generic_quality_floor(self) -> None:
        self.assertEqual(
            [path.relative_to(PACKAGE).as_posix() for path in PACKAGE.rglob("*") if path.is_file()],
            ["SKILL.md"],
        )
        text = (PACKAGE / "SKILL.md").read_text(encoding="utf-8")
        _, frontmatter, _ = text.split("---", 2)
        metadata = yaml.safe_load(frontmatter)
        self.assertEqual(metadata["name"], "engineering-quality-core")
        for required in (
            "shared quality floor",
            "Exercise the real artifact",
            "Side effects",
            "Do not use as the primary workflow",
        ):
            self.assertIn(required, text)
        for forbidden in (
            "/home/",
            "~/.hermes/profiles/",
            "credential file",
            "canary string",
            "customer data",
        ):
            self.assertNotIn(forbidden, text.lower())

    def test_registry_limits_distribution_to_engineering_consumers(self) -> None:
        registry = json.loads((ROOT / "profile-registry.json").read_text())
        consumers = {
            profile
            for profile, record in registry["profiles"].items()
            if "engineering" in record["shared_skill_groups"]
        }
        self.assertEqual(consumers, {"default", "career", "indiedev", "researcheval"})


if __name__ == "__main__":
    unittest.main()
