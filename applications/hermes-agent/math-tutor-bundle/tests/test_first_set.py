from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
REGISTRY = ROOT.parent / "profile-registry.json"


def run(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, *args],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
    )


def load_script(name: str):
    path = SCRIPTS / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class FirstSetTests(unittest.TestCase):
    def build(self, host: str, output: Path) -> dict:
        result = run(str(SCRIPTS / "build_candidate.py"), "--host", host, "--output", str(output))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads((output / "candidate-metadata.json").read_text())

    def test_policy_is_portable_and_maps_every_requirement(self) -> None:
        policy = (ROOT / "SOUL.md").read_text()
        self.assertNotIn("/home/kaki", policy)
        self.assertNotIn("/Users/kaki", policy)
        self.assertIn("~/study_log/math", policy)
        for requirement in range(1, 13):
            self.assertIn(f"R{requirement}", policy)
        for phrase in (
            "canonical files outrank semantic memory",
            "Mathematics hint",
            "Lean/Mathlib hint",
            "no recorded evidence found",
            "full solution",
        ):
            self.assertIn(phrase, policy)

    def test_cross_host_candidates_have_identical_policy_and_no_foreign_home_path(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            tmp = Path(name)
            lawliet = tmp / "lawliet"
            watari = tmp / "watari"
            self.build("lawliet", lawliet)
            self.build("watari", watari)
            self.assertEqual((lawliet / "SOUL.md").read_bytes(), (watari / "SOUL.md").read_bytes())
            lawliet_bytes = b"\n".join(
                path.read_bytes() for path in lawliet.rglob("*") if path.is_file()
            )
            watari_bytes = b"\n".join(
                path.read_bytes() for path in watari.rglob("*") if path.is_file()
            )
            self.assertNotIn(b"/Users/kaki", lawliet_bytes)
            self.assertNotIn(b"/home/kaki", watari_bytes)

    def test_candidate_skill_plane_is_exact_digest_pinned_and_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            candidate = Path(name) / "candidate"
            metadata = self.build("lawliet", candidate)
            allowlist = metadata["skill_allowlist"]
            self.assertEqual(
                [item["name"] for item in allowlist],
                [
                    "math-book-study-workflow",
                    "grounded-math-document-study",
                    "cross-machine-study-environments",
                ],
            )
            self.assertTrue(all(len(item["package_sha256"]) == 64 for item in allowlist))

            checker = load_script("drift_check.py")
            report, ok = checker.check_candidate(candidate, False, None, registry_path=REGISTRY)
            self.assertTrue(ok, report)
            self.assertEqual(report["skill_provenance"]["status"], "pass")

            extra = candidate / "skills/study/math_book_study_workflow"
            extra.mkdir()
            (extra / "SKILL.md").write_text(
                "---\nname: math_book_study_workflow\ndescription: collision\n---\n"
            )
            report, ok = checker.check_candidate(candidate, False, None, registry_path=REGISTRY)
            self.assertFalse(ok)
            self.assertEqual(report["skill_provenance"]["status"], "fail")
            self.assertTrue(report["skill_provenance"]["command_collisions"])

    def test_candidate_skill_plane_rejects_package_byte_and_secret_drift(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            candidate = Path(name) / "candidate"
            self.build("watari", candidate)
            skill = candidate / "skills/study/math-book-study-workflow/SKILL.md"
            skill.write_text(skill.read_text() + "\nsecret = sk-" + "x" * 24 + "\n")
            result = run(str(SCRIPTS / "drift_check.py"), "--candidate", str(candidate), "--registry", str(REGISTRY))
            self.assertNotEqual(result.returncode, 0)
            report = json.loads(result.stdout)
            self.assertIn("package digest mismatch", report["errors"])
            self.assertIn("probable secret material", report["errors"])

    def test_candidate_skill_plane_rejects_platform_incompatible_package(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            candidate = Path(name) / "candidate"
            self.build("lawliet", candidate)
            skill = candidate / "skills/study/grounded-math-document-study/SKILL.md"
            skill.write_text(
                skill.read_text().replace(
                    "platforms: [linux, macos, windows]", "platforms: [macos]"
                )
            )
            result = run(
                str(SCRIPTS / "drift_check.py"),
                "--candidate",
                str(candidate),
                "--registry",
                str(REGISTRY),
            )
            self.assertNotEqual(result.returncode, 0)
            report = json.loads(result.stdout)
            self.assertIn("platform-incompatible skill package", report["errors"])
            self.assertTrue(report["skill_provenance"]["platform_incompatible"])

    def test_runtime_plugin_and_registry_identity_are_separate_dimensions(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            candidate = Path(name) / "candidate"
            metadata = self.build("lawliet", candidate)
            self.assertEqual(metadata["runtime_identity"]["hermes_version"], "0.19.0")
            self.assertEqual(metadata["runtime_identity"]["enabled_plugins"], [])
            result = run(
                str(SCRIPTS / "drift_check.py"),
                "--candidate",
                str(candidate),
                "--registry",
                str(REGISTRY),
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads(result.stdout)
            self.assertEqual(report["runtime_identity"]["status"], "pass")
            self.assertEqual(report["plugin_identity"]["status"], "pass")
            self.assertEqual(report["registry_consistency"]["status"], "pass")

            runtime = candidate / "runtime-identity.json"
            value = json.loads(runtime.read_text())
            value["enabled_plugins"] = ["natural-ok-unified-shadow"]
            runtime.write_text(json.dumps(value))
            result = run(str(SCRIPTS / "drift_check.py"), "--candidate", str(candidate), "--registry", str(REGISTRY))
            self.assertNotEqual(result.returncode, 0)
            report = json.loads(result.stdout)
            self.assertEqual(report["runtime_identity"]["status"], "pass")
            self.assertEqual(report["plugin_identity"]["status"], "fail")
            self.assertEqual(report["registry_consistency"]["status"], "pass")
            self.assertEqual(report["static_policy"]["status"], "fail")
            self.assertIn("plugin-set drift", report["errors"])

    def test_materializer_is_fixture_only_scoped_idempotent_and_preserving(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            tmp = Path(name)
            candidate = tmp / "candidate"
            profile = tmp / "home/.hermes/profiles/math"
            self.build("lawliet", candidate)
            profile.mkdir(parents=True)
            rejected = run(
                str(SCRIPTS / "math_profile_materialize.py"),
                "--candidate",
                str(candidate),
                "--profile-root",
                str(profile),
                "--apply",
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertEqual(list(profile.iterdir()), [])
            (profile / ".math-parity-fixture").write_text("fixture-only\n")
            unmanaged = tmp / "unmanaged-skills"
            unmanaged.mkdir()
            config = {
                "model": {"fallbacks": ["kept"]},
                "plugins": {"enabled": ["kept-plugin"]},
                "skills": {"external_dirs": [str(unmanaged)]},
                "custom": {"sentinel": True},
            }
            (profile / "config.yaml").write_text(yaml.safe_dump(config, sort_keys=False))
            (profile / "config.yaml").chmod(0o600)
            (profile / "unmanaged.txt").write_text("keep\n")
            before_dry = {
                path.relative_to(profile).as_posix(): path.read_bytes()
                for path in profile.rglob("*")
                if path.is_file()
            }

            dry = run(
                str(SCRIPTS / "math_profile_materialize.py"),
                "--candidate",
                str(candidate),
                "--profile-root",
                str(profile),
            )
            self.assertEqual(dry.returncode, 0, dry.stdout + dry.stderr)
            plan = json.loads(dry.stdout)
            self.assertEqual(plan["mode"], "dry-run")
            self.assertFalse(plan["activation_performed"])
            self.assertNotIn("HONCHO_API_KEY", dry.stdout)
            after_dry = {
                path.relative_to(profile).as_posix(): path.read_bytes()
                for path in profile.rglob("*")
                if path.is_file()
            }
            self.assertEqual(after_dry, before_dry)
            self.assertEqual((profile / "unmanaged.txt").read_text(), "keep\n")

            applied = run(
                str(SCRIPTS / "math_profile_materialize.py"),
                "--candidate",
                str(candidate),
                "--profile-root",
                str(profile),
                "--apply",
            )
            self.assertEqual(applied.returncode, 0, applied.stdout + applied.stderr)
            first = {
                path.relative_to(profile).as_posix(): path.read_bytes()
                for path in profile.rglob("*")
                if path.is_file()
            }
            applied_again = run(
                str(SCRIPTS / "math_profile_materialize.py"),
                "--candidate",
                str(candidate),
                "--profile-root",
                str(profile),
                "--apply",
            )
            self.assertEqual(applied_again.returncode, 0, applied_again.stdout + applied_again.stderr)
            second = {
                path.relative_to(profile).as_posix(): path.read_bytes()
                for path in profile.rglob("*")
                if path.is_file()
            }
            self.assertEqual(first, second)
            merged = yaml.safe_load((profile / "config.yaml").read_text())
            self.assertEqual(merged["custom"], {"sentinel": True})
            self.assertEqual(merged["plugins"], {"enabled": ["kept-plugin"]})
            self.assertIn(str(unmanaged), merged["skills"]["external_dirs"])
            self.assertTrue((profile / "skills/parity-study/math-book-study-workflow/SKILL.md").is_file())
            self.assertTrue((profile / "honcho.json").is_file())
            self.assertEqual((profile / "honcho.json").stat().st_mode & 0o777, 0o600)
            self.assertTrue(merged["memory"]["memory_enabled"])
            self.assertEqual(merged["memory"]["provider"], "honcho")
            self.assertFalse((profile / ".env").exists())
            self.assertEqual((profile / "config.yaml").stat().st_mode & 0o777, 0o600)

            honcho = json.loads((profile / "honcho.json").read_text())
            host = honcho["hosts"]["hermes_math"]
            self.assertFalse(host["observation"]["ai"]["observeOthers"])
            self.assertTrue(host["observation"]["ai"]["observeMe"])
            self.assertTrue(host["observation"]["user"]["observeMe"])
            self.assertEqual(
                honcho["continuityPolicy"]["sharedDurableScope"], "user-self"
            )
            self.assertEqual(
                honcho["continuityPolicy"]["observerInferenceScope"], "host-local"
            )

    def test_materializer_rejects_symlink_escape_and_preserves_similar_external_root(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            tmp = Path(name)
            candidate = tmp / "candidate"
            profile = tmp / "profile"
            outside = tmp / "outside"
            self.build("lawliet", candidate)
            profile.mkdir()
            outside.mkdir()
            (profile / ".math-parity-fixture").write_text("fixture-only\n")
            similar = tmp / "unmanaged/skills/parity-study"
            similar.mkdir(parents=True)
            (profile / "config.yaml").write_text(
                yaml.safe_dump({"skills": {"external_dirs": [str(similar)]}})
            )
            (profile / ".parity").symlink_to(outside, target_is_directory=True)
            result = run(
                str(SCRIPTS / "math_profile_materialize.py"),
                "--candidate", str(candidate),
                "--profile-root", str(profile),
                "--apply",
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(list(outside.iterdir()), [])
            self.assertIn(str(similar), (profile / "config.yaml").read_text())

    def test_materializer_dry_run_output_does_not_mutate_filesystem(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            tmp = Path(name)
            candidate = tmp / "candidate"
            profile = tmp / "profile"
            output = tmp / "report.json"
            self.build("watari", candidate)
            profile.mkdir()
            (profile / ".math-parity-fixture").write_text("fixture-only\n")
            result = run(
                str(SCRIPTS / "math_profile_materialize.py"),
                "--candidate", str(candidate),
                "--profile-root", str(profile),
                "--output", str(output),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())

    def test_behavior_harness_covers_all_scenarios_and_proves_both_oracles(self) -> None:
        fixture = json.loads((ROOT / "behavior-fixture.json").read_text())
        self.assertEqual(fixture["fixture_version"], "math-parity-v1")
        self.assertEqual({case["id"] for case in fixture["cases"]}, {f"A{i}" for i in range(1, 19)})
        p0 = {"A1", "A2", "A3", "A4", "A5", "A7", "A8", "A9", "A10", "A11", "A12", "A13", "A14", "A15", "A17"}
        self.assertTrue(all(next(case for case in fixture["cases"] if case["id"] == item)["severity"] == "P0" for item in p0))
        result = run(str(SCRIPTS / "run_behavior_parity.py"), "--fixture", str(ROOT / "behavior-fixture.json"), "--self-test")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["status"], "harness-self-test-pass")
        self.assertEqual(report["pass_oracles"], 18)
        self.assertEqual(report["fail_oracles"], 18)
        self.assertEqual(report["behavioral_compliance_claim"], "not-run")

    def test_behavior_harness_rejects_empty_incomplete_and_inconsistent_records(self) -> None:
        fixture_path = ROOT / "behavior-fixture.json"
        fixture = json.loads(fixture_path.read_text())
        module = load_script("run_behavior_parity.py")

        report, ok = module.evaluate_records(fixture, [])
        self.assertFalse(ok)
        self.assertEqual(report["status"], "fail")
        self.assertTrue(report["coverage_errors"])

        records = []
        for host in ("lawliet", "watari"):
            for scenario in fixture["cases"]:
                for run_index in range(1, fixture["minimum_runs_per_host"] + 1):
                    record = module.synthetic_record(scenario, fail=False)
                    record.update(
                        host=host,
                        candidate_digest="1" * 64,
                        model="gpt-5.6-sol",
                        provider="openai-codex",
                        surface=scenario["surface"],
                        scenario=scenario["id"],
                        run_index=run_index,
                    )
                    records.append(record)
        report, ok = module.evaluate_records(fixture, records)
        self.assertTrue(ok, report)
        records[0]["surface"] = "wrong-surface"
        report, ok = module.evaluate_records(fixture, records)
        self.assertFalse(ok)
        self.assertTrue(report["consistency_errors"])


if __name__ == "__main__":
    unittest.main()
