#!/usr/bin/env python3
import importlib.util
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "gateway_channels_config.py"
SPEC = importlib.util.spec_from_file_location("gateway_channels_config", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load {SCRIPT}")
gateway_channels_config = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = gateway_channels_config
SPEC.loader.exec_module(gateway_channels_config)


class GatewayChannelsConfigTests(unittest.TestCase):
    def create_profile(self, home: Path, profile: str, content: str) -> Path:
        path = gateway_channels_config.config_path(home, profile)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        os.chmod(path, 0o600)
        return path

    def test_updates_default_and_profile_atomically_using_private_mode(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            default = self.create_profile(home, "default", "discord:\n  allowed_channels: ''\nother: keep\n")
            food = self.create_profile(home, "food", "discord:\n  allowed_channels: 1\n")
            os.chmod(default, 0o644)
            os.chmod(food, 0o644)
            gateway_channels_config.apply(home, {"default": "123", "food": "456"})
            self.assertIn("allowed_channels: '123'", default.read_text())
            self.assertIn("other: keep", default.read_text())
            self.assertIn("allowed_channels: '456'", food.read_text())
            self.assertEqual(stat.S_IMODE(default.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(food.stat().st_mode), 0o600)

    def test_validation_failure_prevents_all_writes(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            default = self.create_profile(home, "default", "discord:\n  allowed_channels: old\n")
            before = default.read_text()
            with self.assertRaises(ValueError):
                gateway_channels_config.apply(home, {"default": "123", "missing": "456"})
            self.assertEqual(default.read_text(), before)

            for invalid in ("[]\n", "null\n", "discord: []\n"):
                other = self.create_profile(home, "food", invalid)
                with self.assertRaises(ValueError, msg=invalid):
                    gateway_channels_config.apply(home, {"default": "123", "food": "456"})
                self.assertEqual(default.read_text(), before)
                self.assertEqual(other.read_text(), invalid)


if __name__ == "__main__":
    unittest.main()
