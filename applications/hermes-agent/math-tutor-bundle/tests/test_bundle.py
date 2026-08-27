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

    def test_approved_user_self_topology_is_presence_gated(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            tmp = Path(name)
            candidate = tmp / "lawliet"
            built = run(str(SCRIPTS / "build_candidate.py"), "--host", "lawliet", "--output", str(candidate))
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            topology = tmp / "topology.json"
            topology.write_text(json.dumps({
                "authoritative_checks": {
                    "watari_observer_sees_lawliet_user_conclusion": False,
                    "shared_user_self_scope_visible_from_watari": True,
                    "lawliet_ai_attribution_isolated": True,
                    "watari_ai_attribution_isolated": True,
                },
                "cleanup": {"workspace_deleted": True},
                "secret_readiness": {"HONCHO_API_KEY": "present"},
            }))
            checked = run(
                str(SCRIPTS / "drift_check.py"),
                "--candidate", str(candidate),
                "--topology-report", str(topology),
            )
            self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
            readiness = json.loads(checked.stdout)["semantic_memory_readiness"]
            self.assertEqual(readiness["status"], "ready")
            self.assertEqual(readiness["HONCHO_API_KEY"], "present")
            self.assertFalse(readiness["observer_scope_cross_host_visible"])
            self.assertTrue(readiness["shared_user_self_scope_cross_host_visible"])
            self.assertTrue(readiness["host_specific_ai_scopes_isolated"])
            self.assertEqual(
                readiness["external_test"],
                "pass-user-self-shared-ai-scopes-isolated-cleaned",
            )

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
            forbidden_names = {
                "state.db", "state.db-wal", "state.db-shm", "auth.json", ".env",
                "processes.json", "gateway_state.json", ".ruff_cache", "__pycache__",
            }
            self.assertFalse(forbidden_names.intersection(Path(path).name for path in paths))
            forbidden_parts = {
                "sessions", "logs", "cache", "caches", "cron", "gateway",
                "credentials", "oauth", ".ruff_cache", "__pycache__",
            }
            self.assertFalse(
                [path for path in paths if forbidden_parts.intersection(Path(path).parts)]
            )
            joined = b"\n".join(path.read_bytes() for path in candidate.rglob("*") if path.is_file())
            self.assertNotIn(b"HONCHO_API_KEY=", joined)
            self.assertNotIn(b"sk-", joined)

    def test_credential_report_is_presence_only_and_never_echoes_input(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            candidate = Path(name) / "lawliet"
            built = run(str(SCRIPTS / "build_candidate.py"), "--host", "lawliet", "--output", str(candidate))
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            env = dict(os.environ)
            marker = "credential-marker-that-must-never-appear"
            env["HONCHO_API_KEY"] = marker
            checked = run(str(SCRIPTS / "drift_check.py"), "--candidate", str(candidate), env=env)
            self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
            self.assertNotIn(marker, checked.stdout)
            report = json.loads(checked.stdout)
            self.assertEqual(
                report["semantic_memory_readiness"]["HONCHO_API_KEY"], "present"
            )

    def test_manifest_excludes_caches_and_live_state_from_store_source(self) -> None:
        refresh = importlib.util.spec_from_file_location(
            "refresh_manifest", SCRIPTS / "refresh_manifest.py"
        )
        assert refresh and refresh.loader
        module = importlib.util.module_from_spec(refresh)
        refresh.loader.exec_module(module)
        paths = {path.as_posix() for path in module.payload_files()}
        forbidden = {
            ".coverage", ".mypy_cache", ".pytest_cache", ".ruff_cache",
            "__pycache__", "state.db", "sessions", "logs", "cache", "caches",
            "candidate", "candidates", "dist", "result", "cron", "gateway",
            "auth.json", ".env", "credentials", "oauth",
        }
        self.assertFalse(
            [path for path in paths if forbidden.intersection(Path(path).parts)]
        )
        default_nix = (ROOT / "default.nix").read_text()
        self.assertIn("cleanSourceWith", default_nix)
        for name in (
            ".pytest_cache", ".ruff_cache", "candidates", "result", "state.db",
            "auth.json", ".env", "cron",
        ):
            self.assertIn(name, default_nix)


if __name__ == "__main__":
    unittest.main()
