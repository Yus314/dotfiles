#!/usr/bin/env python3
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "shared-skills/usage-ops/hermes-usage-analysis/scripts/hermes_usage_analyzer.py"
)
SPEC = importlib.util.spec_from_file_location("shared_usage_analyzer", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load {SCRIPT}")
analyzer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(analyzer)


class SharedUsageAnalyzerTests(unittest.TestCase):
    def test_profile_resolves_the_matching_database(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(
            os.environ, {"HOME": tmp}, clear=False
        ):
            profile, path = analyzer.resolve_db_source(
                db=None, profile="career", environ={}
            )
            self.assertEqual(profile, "career")
            self.assertEqual(
                path, Path(tmp) / ".hermes/profiles/career/state.db"
            )

    def test_default_and_environment_profile_resolution(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(
            os.environ, {"HOME": tmp}, clear=False
        ):
            profile, path = analyzer.resolve_db_source(
                db=None, profile=None, environ={}
            )
            self.assertEqual(profile, "default")
            self.assertEqual(path, Path(tmp) / ".hermes/state.db")

            profile, path = analyzer.resolve_db_source(
                db=None,
                profile=None,
                environ={"HERMES_PROFILE": "english"},
            )
            self.assertEqual(profile, "english")
            self.assertEqual(
                path, Path(tmp) / ".hermes/profiles/english/state.db"
            )

    def test_explicit_db_and_profile_are_mutually_exclusive(self):
        with self.assertRaisesRegex(ValueError, "mutually exclusive"):
            analyzer.resolve_db_source(
                db="/tmp/state.db", profile="career", environ={}
            )

    def test_invalid_profile_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "invalid Hermes profile"):
            analyzer.resolve_db_source(
                db=None, profile="../finance", environ={}
            )


if __name__ == "__main__":
    unittest.main()
