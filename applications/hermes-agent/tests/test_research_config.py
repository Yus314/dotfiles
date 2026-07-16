#!/usr/bin/env python3
import importlib.util
import stat
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "research_config.py"
SPEC = importlib.util.spec_from_file_location("research_config", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load {SCRIPT}")
research_config = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = research_config
SPEC.loader.exec_module(research_config)


class ResearchConfigTests(unittest.TestCase):
    def test_applies_expected_settings_preserves_unknown_and_uses_private_mode(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            path = home / ".hermes/config.yaml"
            path.parent.mkdir(parents=True)
            path.write_text("unknown:\n  keep: true\nweb:\n  other: value\n")
            path.chmod(0o644)
            research_config.apply(path, home)
            result = yaml.safe_load(path.read_text())
            self.assertTrue(result["unknown"]["keep"])
            self.assertEqual(result["web"]["backend"], "firecrawl")
            self.assertEqual(result["web"]["other"], "value")
            self.assertEqual(result["model"]["provider"], "openai-codex")
            self.assertEqual(
                result["providers"]["openai-codex"]["models"]["gpt-5.6-sol"]["stale_timeout_seconds"],
                300,
            )
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_rejects_non_mapping_without_replacing_original(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            path = home / ".hermes/config.yaml"
            path.parent.mkdir(parents=True)
            for invalid in ("[]\n", "null\n", "web: []\n", "mcp_servers:\n  research_providers: bad\n"):
                path.write_text(invalid)
                with self.assertRaises(ValueError, msg=invalid):
                    research_config.apply(path, home)
                self.assertEqual(path.read_text(), invalid)

    def test_creates_missing_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            path = home / ".hermes/config.yaml"
            research_config.apply(path, home)
            self.assertTrue(path.is_file())
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
