#!/usr/bin/env python3
"""Read-only candidate/live drift report with four independent dimensions."""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import subprocess
from pathlib import Path


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fp(*parts: str) -> str:
    return hashlib.sha256("\0".join(parts).encode()).hexdigest()


def git_probe(path: Path) -> dict:
    if not path.exists():
        return {"path": str(path), "status": "missing"}
    top = subprocess.run(["git", "-C", str(path), "rev-parse", "--show-toplevel"], text=True, capture_output=True)
    if top.returncode:
        return {"path": str(path), "status": "not-git"}
    revision = subprocess.run(["git", "-C", str(path), "rev-parse", "HEAD"], text=True, capture_output=True, check=True).stdout.strip()
    porcelain = subprocess.run(["git", "-C", str(path), "status", "--porcelain=v1"], text=True, capture_output=True, check=True).stdout
    return {"path": str(path), "status": "ok", "revision": revision, "clean": porcelain == "", "dirty_entries": len(porcelain.splitlines())}


def path_forbidden(rel: str, patterns: list[str]) -> bool:
    parts = Path(rel).parts
    return any(fnmatch.fnmatch(part.lower(), pattern.lower()) for part in parts for pattern in patterns)


def check_candidate(candidate: Path, probe_live: bool, dotfiles_repo: Path | None) -> tuple[dict, bool]:
    errors: list[str] = []
    metadata = json.loads((candidate / "candidate-metadata.json").read_text())
    sync = json.loads((candidate / "sync-inputs.json").read_text())
    actual_paths = sorted(path.relative_to(candidate).as_posix() for path in candidate.rglob("*") if path.is_file())

    effective_actual = {
        rel: digest(candidate / rel)
        for rel in metadata["effective_file_digests"]
        if (candidate / rel).is_file()
    }
    if effective_actual != metadata["effective_file_digests"]:
        errors.append("effective file digest mismatch")
    expected_paths = sorted(metadata["effective_file_digests"])
    generated_paths = sorted(set(actual_paths) - {"candidate-metadata.json", "sync-inputs.json"})
    if generated_paths != expected_paths:
        errors.append("undeclared candidate output path")
    forbidden_hits = [rel for rel in actual_paths if path_forbidden(rel, sync["forbidden_path_patterns"])]
    if forbidden_hits:
        errors.append("forbidden sync path present")

    honcho = json.loads((candidate / "honcho.json").read_text())
    host_cfg = honcho["hosts"]["hermes_math"]
    hmeta = metadata["honcho"]
    topology_ok = (
        honcho["workspace"] == hmeta["workspace"]
        and honcho["peerName"] == hmeta["user_peer"]
        and host_cfg["aiPeer"] == hmeta["ai_peer"]
        and len(set(hmeta["expected_distinct_ai_peers"])) == 2
        and fp(hmeta["workspace"], hmeta["user_peer"]) == hmeta["user_peer_fingerprint"]
        and fp(hmeta["workspace"], hmeta["ai_peer"]) == hmeta["ai_peer_fingerprint"]
    )
    if not topology_ok:
        errors.append("Honcho topology/fingerprint mismatch")

    config = json.loads((candidate / "config.fragment.json").read_text())
    model_ok = (
        config["model"].get("provider") == metadata["expected_model"].get("provider")
        and config["model"].get("default") == metadata["expected_model"].get("model")
    )
    skill_names = sorted(path.name for path in (candidate / "skills" / "study").iterdir() if path.is_dir())
    expected_skills = sorted(item["name"] for item in metadata["skill_allowlist"])
    skills_ok = skill_names == expected_skills
    if not model_ok:
        errors.append("model/provider mismatch")
    if not skills_ok:
        errors.append("skill allowlist/source mismatch")

    overlay = metadata["host_overlay"]
    undeclared_overlay = sorted(set(overlay) - set(metadata["overlay_allowlist"]) - {"schema_version", "overlay_allowlist"})
    if undeclared_overlay:
        errors.append("undeclared overlay field")

    repos = {}
    for name, configured in overlay["repository_paths"].items():
        repos[name] = git_probe(Path(configured)) if probe_live else {"path": configured, "status": "not-probed-candidate-only"}
    if dotfiles_repo:
        repos["dotfiles"] = git_probe(dotfiles_repo)

    configured_repo_reports = [repos[name] for name in overlay["repository_paths"]]
    repositories_ready = probe_live and all(
        item.get("status") == "ok" and item.get("clean") is True
        for item in configured_repo_reports
    )
    canonical_status = "fail" if forbidden_hits else ("pass" if repositories_ready else ("blocked" if probe_live else "candidate-only"))

    fixture = json.loads((candidate / "behavior-fixture.json").read_text())
    behavior_ready = bool(fixture.get("cases")) and all(case.get("required_claims") and case.get("forbidden_claims") for case in fixture["cases"])
    report = {
        "schema_version": 1,
        "host": overlay["host"],
        "canonical_content": {
            "status": canonical_status,
            "repositories": repos,
            "repositories_ready": repositories_ready,
            "ladr_artifacts": overlay["ladr_artifacts"],
            "forbidden_sync_hits": forbidden_hits,
        },
        "static_policy": {
            "status": "pass" if effective_actual == metadata["effective_file_digests"] and model_ok and skills_ok and not undeclared_overlay else "fail",
            "bundle_aggregate_sha256": metadata["bundle_aggregate_sha256"],
            "effective_file_digests": metadata["effective_file_digests"],
            "model_provider_match": model_ok,
            "selected_skill_sources_match": skills_ok,
            "selected_skills": metadata["skill_allowlist"],
            "undeclared_overlay_fields": undeclared_overlay,
        },
        "semantic_memory_readiness": {
            "status": "ready" if topology_ok and os.getenv("HONCHO_API_KEY") else "blocked",
            "topology_match": topology_ok,
            "workspace_user_peer_fingerprint": hmeta["user_peer_fingerprint"],
            "ai_peer_fingerprint": hmeta["ai_peer_fingerprint"],
            "distinct_ai_peers": hmeta["expected_distinct_ai_peers"],
            "HONCHO_API_KEY": "present" if os.getenv("HONCHO_API_KEY") else "missing",
            "external_test": "prepared-not-run",
        },
        "behavior_test": {
            "status": "prepared-not-run" if behavior_ready else "fail",
            "fixture_cases": [case["id"] for case in fixture.get("cases", [])],
            "activation_required": True,
        },
        "errors": errors,
    }
    return report, not errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--probe-live", action="store_true")
    parser.add_argument("--dotfiles-repo", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report, ok = check_candidate(args.candidate.resolve(), args.probe_live, args.dotfiles_repo.resolve() if args.dotfiles_repo else None)
    text = json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
