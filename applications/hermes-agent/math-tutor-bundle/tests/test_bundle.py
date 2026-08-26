from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"


def run(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    command = [sys.executable, *args]
    return subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True)


def file_map(root: Path) -> dict[str, bytes]:
    return {
        path.relative_to(root).as_posix(): path.read_bytes()
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


class BundleTests(unittest.TestCase):
    def test_manifest_is_current(self) -> None:
        result = run(str(SCRIPTS / "refresh_manifest.py"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_candidates_are_deterministic_and_overlay_bounded(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            tmp = Path(name)
            built: dict[str, Path] = {}
            for host in ("lawliet", "watari"):
                first = tmp / f"{host}-1"
                second = tmp / f"{host}-2"
                for output in (first, second):
                    result = run(str(SCRIPTS / "build_candidate.py"), "--host", host, "--output", str(output))
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(file_map(first), file_map(second))
                built[host] = first

                env = dict(os.environ)
                env.pop("HONCHO_API_KEY", None)
                checked = run(str(SCRIPTS / "drift_check.py"), "--candidate", str(first), env=env)
                self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
                report = json.loads(checked.stdout)
                self.assertEqual(report["canonical_content"]["status"], "candidate-only")
                self.assertEqual(report["static_policy"]["status"], "pass")
                self.assertEqual(report["semantic_memory_readiness"]["status"], "blocked")
                self.assertEqual(report["semantic_memory_readiness"]["HONCHO_API_KEY"], "missing")
                self.assertEqual(report["behavior_test"]["status"], "prepared-not-run")

            left = file_map(built["lawliet"])
            right = file_map(built["watari"])
            differing = sorted(path for path in left if left[path] != right[path])
            self.assertEqual(differing, ["candidate-metadata.json", "config.fragment.json", "honcho.json"])
            self.assertEqual(sorted(left), sorted(right))

    def test_allowlist_is_exact_and_minimal(self) -> None:
        manifest = json.loads((ROOT / "manifest.json").read_text())
        self.assertEqual(
            [item["name"] for item in manifest["skill_allowlist"]],
            ["math-book-study-workflow", "grounded-math-document-study", "cross-machine-study-environments"],
        )

    def test_checker_rejects_digest_drift_and_forbidden_state(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            candidate = Path(name) / "lawliet"
            built = run(str(SCRIPTS / "build_candidate.py"), "--host", "lawliet", "--output", str(candidate))
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            (candidate / "SOUL.md").write_text("drift\n")
            (candidate / "state.db").write_bytes(b"not sqlite")
            checked = run(str(SCRIPTS / "drift_check.py"), "--candidate", str(candidate))
            self.assertNotEqual(checked.returncode, 0)
            report = json.loads(checked.stdout)
            self.assertIn("effective file digest mismatch", report["errors"])
            self.assertIn("forbidden sync path present", report["errors"])

    def test_candidate_contains_no_secret_material_or_live_state(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            candidate = Path(name) / "watari"
            built = run(str(SCRIPTS / "build_candidate.py"), "--host", "watari", "--output", str(candidate))
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            paths = [path.relative_to(candidate).as_posix() for path in candidate.rglob("*") if path.is_file()]
            forbidden_names = {"state.db", "state.db-wal", "state.db-shm", "auth.json", ".env", "processes.json"}
            self.assertFalse(forbidden_names.intersection(Path(path).name for path in paths))
            joined = b"\n".join(path.read_bytes() for path in candidate.rglob("*") if path.is_file())
            self.assertNotIn(b"HONCHO_API_KEY=", joined)
            self.assertNotIn(b"sk-", joined)


if __name__ == "__main__":
    unittest.main()
