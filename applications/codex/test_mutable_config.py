"""Regression tests for Codex's Home Manager mutable config migration."""

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import tomlkit
from mutable_config import materialize


class MutableConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.target = self.root / "codex" / "config.toml"
        self.source = self.root / "managed.toml"
        self.source.write_text(
            'approval_policy = "on-request"\n[tui]\nnotifications = ["approval-requested"]\n'
        )

    def existing(self, text):
        self.target.parent.mkdir(exist_ok=True)
        self.target.write_text(text)

    def test_initial_creation(self):
        materialize(self.source, self.target)
        self.assertFalse(self.target.is_symlink())
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(
            tomlkit.parse(self.target.read_text()),
            tomlkit.parse(self.source.read_text()),
        )

    def test_migrate_symlink_without_touching_source(self):
        self.target.parent.mkdir()
        old = self.root / "old-store-config"
        original = '[projects."/work"]\ntrust_level = "trusted"\n'
        old.write_text(original)
        old.chmod(0o444)
        self.target.symlink_to(old)
        materialize(self.source, self.target)
        self.assertFalse(self.target.is_symlink())
        self.assertEqual(old.read_text(), original)
        self.assertEqual(
            tomlkit.parse(self.target.read_text())["projects"]["/work"]["trust_level"],
            "trusted",
        )
        self.assertEqual(
            next(self.target.parent.glob("config.toml.backup-*")).read_text(), original
        )

    def test_preserve_runtime_keys_and_comments(self):
        self.existing(
            '# personal\nmodel = "custom"\napproval_policy = "never"\n[tui]\ntheme = "dark"\nnotifications = false\n[projects."/work"]\ntrust_level = "trusted"\n'
        )
        materialize(self.source, self.target)
        result = tomlkit.parse(self.target.read_text())
        self.assertIn("# personal", self.target.read_text())
        self.assertEqual(result["model"], "custom")
        self.assertEqual(result["approval_policy"], "on-request")
        self.assertEqual(result["tui"]["theme"], "dark")
        self.assertEqual(result["tui"]["notifications"], ["approval-requested"])
        self.assertEqual(result["projects"]["/work"]["trust_level"], "trusted")

    def test_repeated_activation_is_noop(self):
        materialize(self.source, self.target)
        before = self.target.stat()
        materialize(self.source, self.target)
        self.assertEqual(self.target.stat().st_mtime_ns, before.st_mtime_ns)
        self.assertEqual(list(self.target.parent.glob("config.toml.backup-*")), [])

    def test_invalid_config_is_not_overwritten(self):
        self.existing("[invalid")
        with self.assertRaises(tomlkit.exceptions.ParseError):
            materialize(self.source, self.target)
        self.assertEqual(self.target.read_text(), "[invalid")

    def test_dangling_symlink_is_not_overwritten(self):
        self.target.parent.mkdir()
        self.target.symlink_to(self.root / "missing")
        with self.assertRaises(FileNotFoundError):
            materialize(self.source, self.target)
        self.assertTrue(self.target.is_symlink())

    def test_failed_replace_preserves_original(self):
        self.existing('model = "keep"\n')
        with (
            patch("mutable_config.os.replace", side_effect=OSError("failure")),
            self.assertRaises(OSError),
        ):
            materialize(self.source, self.target)
        self.assertEqual(self.target.read_text(), 'model = "keep"\n')
        self.assertEqual(list(self.target.parent.glob(".config.toml-*")), [])

    def test_reapply_keeps_new_trust(self):
        materialize(self.source, self.target)
        with self.target.open("a") as stream:
            stream.write('\n[projects."/new"]\ntrust_level = "trusted"\n')
        self.source.write_text('approval_policy = "untrusted"\n')
        materialize(self.source, self.target)
        result = tomlkit.parse(self.target.read_text())
        self.assertEqual(result["projects"]["/new"]["trust_level"], "trusted")
        self.assertEqual(result["approval_policy"], "untrusted")


if __name__ == "__main__":
    unittest.main()
