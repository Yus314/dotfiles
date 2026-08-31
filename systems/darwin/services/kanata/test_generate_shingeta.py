#!/usr/bin/env python3
"""Executable invariants for the offline macOS Shingeta artifact."""

import importlib.util
import os
import re
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
if len(HERE.parents) >= 4:
    ROOT = HERE.parents[3]
else:
    ROOT = Path("/")
GENERATOR_PATH = Path(
    os.environ.get(
        "SHINGETA_GENERATOR",
        ROOT / "systems/nixos/services/kanata/generate_shingeta.py",
    )
)
SOURCE = Path(
    os.environ.get(
        "SHINGETA_SOURCE", ROOT / "systems/nixos/services/xremap/shingeta.yml"
    )
)
GENERATED = Path(os.environ.get("SHINGETA_MAC_GENERATED", HERE / "shingeta.kbd"))
AQUASKK_KEYMAP = Path(
    os.environ.get("AQUASKK_KEYMAP", ROOT / "homes/darwin/keymap.conf")
)
LINUX_GENERATED_ENV = os.environ.get("SHINGETA_LINUX_GENERATED")
LINUX_GENERATED = Path(LINUX_GENERATED_ENV) if LINUX_GENERATED_ENV else None

spec = importlib.util.spec_from_file_location("generate_shingeta", GENERATOR_PATH)
assert spec is not None and spec.loader is not None
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class MacShingetaGenerationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.default, cls.shinyou = generator.load_maps(SOURCE)
        cls.text, cls.singles, cls.chords, cls.source_keys = generator.generate_macos(
            cls.default, cls.shinyou
        )

    def test_exact_canonical_counts_and_timing(self):
        self.assertEqual(self.singles, 32)
        self.assertEqual(self.chords, 102)
        self.assertEqual(len(generator.MAC_LOGICAL_TO_PHYSICAL), 32)
        self.assertEqual(len(set(generator.MAC_LOGICAL_TO_PHYSICAL.values())), 32)
        self.assertEqual(
            {rule["timeout_millis"] for rule in self.shinyou.values()}, {40}
        )
        chord_lines = re.findall(
            r"^  \([^\n]+\) \(macro [^\n]+\) 40 first-release \(ascii\)$",
            self.text,
            flags=re.MULTILINE,
        )
        self.assertEqual(len(chord_lines), 102)

    def test_committed_artifacts_are_deterministic(self):
        self.assertEqual(self.text, GENERATED.read_text())
        linux_text, singles, chords, source_keys = generator.generate_linux(
            self.default, self.shinyou
        )
        self.assertEqual((singles, chords, source_keys), (32, 102, 52))
        if LINUX_GENERATED is not None:
            self.assertEqual(linux_text, LINUX_GENERATED.read_text())
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "first.kbd"
            second = Path(directory) / "second.kbd"
            first.write_text(self.text)
            second.write_text(generator.generate_macos(self.default, self.shinyou)[0])
            self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_explicit_aquaskk_transition_model(self):
        self.assertIn(
            "to-shingeta (multi (macro kana) (layer-switch shingeta))", self.text
        )
        self.assertIn("to-ascii (multi (macro l) (layer-switch ascii))", self.text)
        self.assertIn("(deflayer ascii", self.text)
        self.assertIn("(deflayer shingeta", self.text)
        self.assertEqual(self.text.count("first-release (ascii)"), 102)
        self.assertNotIn("cmd", self.text.lower())
        self.assertNotIn("tcp", self.text.lower())

    def test_current_aquaskk_katakana_transition_key(self):
        # The real-device AquaSKK state-machine probe established `q` as the
        # non-convertible katakana action key on both platforms. Do not revive
        # the earlier macOS-only printable apostrophe override.
        self.assertEqual(self.shinyou["v"]["timeout_key"], "q")
        self.assertNotIn("macos_timeout_key", self.shinyou["v"])
        self.assertIn("single-v (macro q)", self.text)
        toggle_kana = re.findall(
            r"^ToggleKana\s+(\S+)\s*$",
            AQUASKK_KEYMAP.read_text(),
            flags=re.MULTILINE,
        )
        self.assertEqual(toggle_kana, ["q"])
        linux_text = generator.generate_linux(self.default, self.shinyou)[0]
        self.assertIn("single-v (macro q)", linux_text)

    def test_macos_base_and_shift_event_semantics(self):
        expected = {
            "1": ("S-1", "(unshift 9)"),
            "2": ("S-7", "(unshift 7)"),
            "3": ("S-,", "(unshift 5)"),
            "4": ("[", "(unshift 3)"),
            "5": ("S-[", "(unshift 1)"),
            "6": ("S-grv", "(unshift 8)"),
            "7": ("S-]", "(unshift 0)"),
            "8": ("]", "(unshift 2)"),
            "9": ("S-.", "(unshift 4)"),
            "0": ("S-4", "(unshift 6)"),
            "-": ("(unshift bksl)", "S-3"),
            "=": ("S-2", "(unshift grv)"),
            "r": (".", "(unshift ;)"),
            "t": ("=", "S-;"),
            "]": ("S-5", "S-6"),
            "¥": ("S-bksl", "S-/"),
            "x": ("-", "S-8"),
            "c": (",", "S--"),
            "v": ("S-9", "S-="),
            "b": ("apos", "S-apos"),
            "ro": ("S-0", "(unshift /)"),
        }
        for key, actions in expected.items():
            self.assertEqual(generator.MAC_BASE_ACTIONS[key], actions)
        self.assertIn(
            "base-yen (switch (lsft rsft) S-/ break () S-bksl break)",
            self.text,
        )
        self.assertNotIn("base-bksl", self.text)
        self.assertEqual(len(generator.MAC_BASE_ACTIONS), 47)
        self.assertIn(generator.MAC_DEVICE_PLACEHOLDER, self.text)

    def test_lean_symbol_priorities_reclaim_duplicate_paths(self):
        self.assertEqual(generator.MAC_BASE_ACTIONS["-"], ("(unshift bksl)", "S-3"))
        self.assertEqual(generator.MAC_BASE_ACTIONS["1"][0], "S-1")
        self.assertEqual(
            generator.MAC_BASE_ACTIONS["¥"],
            ("S-bksl", "S-/"),
        )
        self.assertIn(
            "base-minus (switch (lsft rsft) S-3 break () (unshift bksl) break)",
            self.text,
        )
        self.assertIn(
            "base-yen (switch (lsft rsft) S-/ break () S-bksl break)",
            self.text,
        )


if __name__ == "__main__":
    unittest.main()
