#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

import yaml

MODULE_PATH = Path(__file__).with_name("computer_use_config.py")
SPEC = importlib.util.spec_from_file_location("computer_use_config", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ComputerUseConfigTest(unittest.TestCase):
    def test_adds_only_read_only_pilot_tools_and_preserves_other_config(self) -> None:
        config = {
            "model": {"default": "keep-me"},
            "mcp_servers": {"research_providers": {"command": "uv", "args": ["run"]}},
        }
        actual = MODULE.configured(config, "/nix/store/example/bin/computer-use-linux")
        self.assertEqual(actual["model"]["default"], "keep-me")
        self.assertIn("research_providers", actual["mcp_servers"])
        server = actual["mcp_servers"]["computer-use-linux"]
        self.assertEqual(
            server["tools"]["include"],
            ["doctor", "list_apps", "get_app_state"],
        )
        self.assertEqual(server["args"], [])
        self.assertFalse(server["sampling"]["enabled"])

    def test_apply_is_idempotent_and_private(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.yaml"
            path.write_text("unrelated: true\n")
            MODULE.apply(path, "/nix/store/example/bin/computer-use-linux")
            first = path.read_bytes()
            MODULE.apply(path, "/nix/store/example/bin/computer-use-linux")
            self.assertEqual(path.read_bytes(), first)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertTrue(yaml.safe_load(first)["unrelated"])

    def test_rejects_non_mapping_server_section(self) -> None:
        with self.assertRaises(ValueError):
            MODULE.configured({"mcp_servers": []}, "/bin/false")


if __name__ == "__main__":
    unittest.main()
