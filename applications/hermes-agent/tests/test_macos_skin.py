"""Default-profile macOS skin policy; no user config or credentials are read."""

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).parents[1] / "scripts" / "macos_skin.py"
spec = importlib.util.spec_from_file_location("macos_skin", SCRIPT)
assert spec is not None and spec.loader is not None
skin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(skin)


class MacosSkinTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        (self.home / "skins").mkdir()
        for name in ("modus-vivendi", "modus-operandi"):
            (self.home / "skins" / f"{name}.yaml").write_text(f"name: {name}\n")
        self.env = patch.dict(os.environ, {"HERMES_MACOS_SKIN_HOME": str(self.home)}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.platform = patch.object(sys, "platform", "darwin")
        self.platform.start()
        self.addCleanup(self.platform.stop)
        self.stdin = patch.object(sys.stdin, "isatty", return_value=True)
        self.stdout = patch.object(sys.stdout, "isatty", return_value=True)
        self.stdin.start()
        self.stdout.start()
        self.addCleanup(self.stdin.stop)
        self.addCleanup(self.stdout.stop)
        skin.detect_appearance.cache_clear()

    def enable(self, **args):
        skin.prepare_chat(SimpleNamespace(**args), self.home)

    def test_interactive_default_enabled(self):
        self.enable()
        self.assertEqual(os.environ[skin.SESSION_HOME], str(self.home.resolve()))

    def test_named_profile_not_enabled(self):
        skin.prepare_chat(SimpleNamespace(), self.home / "profiles/math")
        self.assertNotIn(skin.SESSION_HOME, os.environ)

    def test_inherited_marker_cleared_for_query(self):
        self.enable()
        self.enable(query="test")
        self.assertNotIn(skin.SESSION_HOME, os.environ)

    def test_empty_query_is_noninteractive(self):
        self.enable(query="")
        self.assertNotIn(skin.SESSION_HOME, os.environ)

    def test_ignore_user_config_excluded(self):
        self.enable(ignore_user_config=True)
        self.assertNotIn(skin.SESSION_HOME, os.environ)

    def test_ssh_excluded(self):
        for key in ("SSH_CONNECTION", "SSH_TTY", "SSH_CLIENT"):
            with self.subTest(key=key), patch.dict(os.environ, {key: "present"}):
                self.enable()
                self.assertNotIn(skin.SESSION_HOME, os.environ)

    def test_safe_mode_and_ignored_config_env_excluded(self):
        self.enable(safe_mode=True)
        self.assertNotIn(skin.SESSION_HOME, os.environ)
        with patch.dict(os.environ, {"HERMES_IGNORE_USER_CONFIG": "1"}):
            self.enable()
            self.assertNotIn(skin.SESSION_HOME, os.environ)

    def test_opt_out(self):
        os.environ["HERMES_MACOS_SKIN_SYNC"] = "0"
        self.enable()
        self.assertNotIn(skin.SESSION_HOME, os.environ)

    def test_non_tty_excluded(self):
        for stream in (sys.stdin, sys.stdout):
            with self.subTest(stream=stream), patch.object(stream, "isatty", return_value=False):
                self.enable()
                self.assertNotIn(skin.SESSION_HOME, os.environ)

    def test_linux_excluded(self):
        with patch.object(sys, "platform", "linux"):
            self.enable()
        self.assertNotIn(skin.SESSION_HOME, os.environ)

    def test_unconfigured_wrapper_excluded(self):
        os.environ.pop("HERMES_MACOS_SKIN_HOME")
        self.enable()
        self.assertNotIn(skin.SESSION_HOME, os.environ)

    def test_dark_and_light_selection_without_mutation(self):
        self.enable()
        for appearance, expected in (("dark", "modus-vivendi"), ("light", "modus-operandi")):
            for saved in ("default", "modus-vivendi", "modus-operandi"):
                with self.subTest(appearance=appearance, saved=saved):
                    with patch.object(skin, "detect_appearance", return_value=appearance):
                        self.assertEqual(skin.select_skin(saved, self.home), expected)
        self.assertFalse((self.home / "config.yaml").exists())

    def test_manual_custom_skin_preserved(self):
        self.enable()
        with patch.object(skin, "detect_appearance") as detect:
            self.assertEqual(skin.select_skin("slate", self.home), "slate")
            detect.assert_not_called()

    def test_profile_boundary_rechecked_in_child(self):
        self.enable()
        with patch.object(skin, "detect_appearance") as detect:
            self.assertEqual(skin.select_skin("default", self.home / "profiles/math"), "default")
            detect.assert_not_called()

    def test_no_marker_no_probe(self):
        with patch.object(skin, "detect_appearance") as detect:
            self.assertEqual(skin.select_skin("default", self.home), "default")
            detect.assert_not_called()

    def test_missing_skin_preserves_saved(self):
        self.enable()
        (self.home / "skins/modus-vivendi.yaml").unlink()
        with patch.object(skin, "detect_appearance", return_value="dark"):
            self.assertEqual(skin.select_skin("default", self.home), "default")

    def test_failed_probe_preserves_saved(self):
        self.enable()
        with patch.object(skin, "detect_appearance", return_value=None):
            self.assertEqual(skin.select_skin("modus-operandi", self.home), "modus-operandi")

    def test_probe_parses_global_preferences_and_caches(self):
        for value, expected in (("Dark", "dark"), (None, "light"), ("Unexpected", None)):
            with self.subTest(value=value):
                skin.detect_appearance.cache_clear()
                payload = {} if value is None else {"AppleInterfaceStyle": value}
                with patch.object(skin.subprocess, "run", return_value=SimpleNamespace(stdout=skin.plistlib.dumps(payload))) as run:
                    self.assertEqual(skin.detect_appearance(), expected)
                    self.assertEqual(skin.detect_appearance(), expected)
                    self.assertEqual(run.call_count, 1)
                    self.assertEqual(run.call_args.args[0], ["/usr/bin/defaults", "export", "NSGlobalDomain", "-"])
                    self.assertEqual(run.call_args.kwargs["timeout"], 2)

    def test_probe_errors_are_nonfatal(self):
        for error in (OSError("unavailable"), subprocess.TimeoutExpired("defaults", 2), subprocess.CalledProcessError(1, "defaults")):
            with self.subTest(error=type(error)), patch.object(skin.subprocess, "run", side_effect=error):
                skin.detect_appearance.cache_clear()
                self.assertIsNone(skin.detect_appearance())
        for data in (b"not a plist", skin.plistlib.dumps([])):
            with patch.object(skin.subprocess, "run", return_value=SimpleNamespace(stdout=data)):
                skin.detect_appearance.cache_clear()
                self.assertIsNone(skin.detect_appearance())


if __name__ == "__main__":
    unittest.main()
