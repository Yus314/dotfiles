#!/usr/bin/env python3
"""Read-only math candidate drift report with independent evidence dimensions."""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

SECRET_PATTERNS = (
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(rb"\bsk-(?:or-v1-)?[A-Za-z0-9_-]{20,}\b"),
    re.compile(rb"\bgh[oprsu]_[A-Za-z0-9]{20,}\b"),
    re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    re.compile(rb"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
    re.compile(rb"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"),
)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def package_digest(root: Path) -> str:
    value = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        relative = path.relative_to(root).as_posix().encode()
        content = path.read_bytes()
        value.update(len(relative).to_bytes(8, "big"))
        value.update(relative)
        value.update(len(content).to_bytes(8, "big"))
        value.update(content)
    return value.hexdigest()


def fp(*parts: str) -> str:
    return hashlib.sha256("\0".join(parts).encode()).hexdigest()


def command_slug(name: str) -> str:
    slug = name.lower().replace("_", "-").replace(" ", "-")
    slug = re.sub(r"[^a-z0-9-]", "", slug)
    return re.sub(r"-{2,}", "-", slug).strip("-")


def declared_skill_name(package: Path) -> str:
    skill = package / "SKILL.md"
    if not skill.is_file():
        return package.name
    match = re.search(r"(?m)^name:\s*['\"]?([a-z0-9_-]+)", skill.read_text(encoding="utf-8"))
    return match.group(1) if match else package.name


def declared_platforms(package: Path) -> set[str]:
    skill = package / "SKILL.md"
    if not skill.is_file():
        return set()
    match = re.search(r"(?m)^platforms:\s*\[([^]]*)\]", skill.read_text(encoding="utf-8"))
    if not match:
        return set()
    return {
        item.strip().strip("'\"").lower()
        for item in match.group(1).split(",")
        if item.strip()
    }


def git_probe(path: Path) -> dict:
    if not path.exists():
        return {"path": str(path), "status": "missing"}
    top = subprocess.run(
        ["git", "-C", str(path), "rev-parse", "--show-toplevel"],
        text=True,
        capture_output=True,
    )
    if top.returncode:
        return {"path": str(path), "status": "not-git"}
    revision = subprocess.run(
        ["git", "-C", str(path), "rev-parse", "HEAD"],
        text=True,
        capture_output=True,
        check=True,
    ).stdout.strip()
    porcelain = subprocess.run(
        ["git", "-C", str(path), "status", "--porcelain=v1"],
        text=True,
        capture_output=True,
        check=True,
    ).stdout
    return {
        "path": str(path),
        "status": "ok",
        "revision": revision,
        "clean": porcelain == "",
        "dirty_entries": len(porcelain.splitlines()),
    }


def path_forbidden(rel: str, patterns: list[str]) -> bool:
    parts = Path(rel).parts
    return any(
        fnmatch.fnmatch(part.lower(), pattern.lower())
        for part in parts
        for pattern in patterns
    )


def registry_contract(registry_path: Path) -> dict:
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    math = registry["profiles"]["math"]
    parity = math["parity_candidate"]
    return {
        "role": math["role"],
        "canonical_root": parity["canonical_root"],
        "summary_path": parity["summary_path"],
        "summary_policy": math["summary_policy"],
        "skill_packages": parity["skill_packages"],
        "memory_workspace": parity["memory_workspace"],
        "semantic_memory_readiness": parity["semantic_memory_readiness"],
        "continuity_policy": parity["continuity_policy"],
        "runtime_identity": parity["runtime_identity"],
    }


def check_candidate(
    candidate: Path,
    probe_live: bool,
    dotfiles_repo: Path | None,
    topology_report: Path | None = None,
    registry_path: Path | None = None,
) -> tuple[dict, bool]:
    errors: list[str] = []
    metadata = json.loads((candidate / "candidate-metadata.json").read_text())
    sync = json.loads((candidate / "sync-inputs.json").read_text())
    actual_paths = sorted(
        path.relative_to(candidate).as_posix()
        for path in candidate.rglob("*")
        if path.is_file()
    )

    effective_actual = {
        rel: digest(candidate / rel)
        for rel in metadata["effective_file_digests"]
        if (candidate / rel).is_file()
    }
    effective_match = effective_actual == metadata["effective_file_digests"]
    if not effective_match:
        errors.append("effective file digest mismatch")
    expected_paths = sorted(metadata["effective_file_digests"])
    generated_paths = sorted(
        set(actual_paths) - {"candidate-metadata.json", "sync-inputs.json"}
    )
    if generated_paths != expected_paths:
        errors.append("undeclared candidate output path")
    forbidden_hits = [
        rel for rel in actual_paths if path_forbidden(rel, sync["forbidden_path_patterns"])
    ]
    if forbidden_hits:
        errors.append("forbidden sync path present")

    secret_hits = []
    for rel in actual_paths:
        content = (candidate / rel).read_bytes()
        if any(pattern.search(content) for pattern in SECRET_PATTERNS):
            secret_hits.append(rel)
    if secret_hits:
        errors.append("probable secret material")

    honcho = json.loads((candidate / "honcho.json").read_text())
    host_cfg = honcho["hosts"]["hermes_math"]
    hmeta = metadata["honcho"]
    topology_ok = (
        honcho["workspace"] == hmeta["workspace"]
        and honcho["peerName"] == hmeta["user_peer"]
        and host_cfg["aiPeer"] == hmeta["ai_peer"]
        and len(set(hmeta["expected_distinct_ai_peers"])) == 2
        and hmeta["shared_durable_scope"] == "user-self"
        and hmeta["observer_inference_scope"] == "host-local"
        and honcho.get("continuityPolicy", {}).get("sharedDurableScope") == "user-self"
        and honcho.get("continuityPolicy", {}).get("observerInferenceScope") == "host-local"
        and host_cfg.get("observation", {}).get("ai", {}).get("observeOthers") is False
        and host_cfg.get("observation", {}).get("ai", {}).get("observeMe") is True
        and host_cfg.get("observation", {}).get("user", {}).get("observeMe") is True
        and fp(hmeta["workspace"], hmeta["user_peer"])
        == hmeta["user_peer_fingerprint"]
        and fp(hmeta["workspace"], hmeta["ai_peer"])
        == hmeta["ai_peer_fingerprint"]
    )
    if not topology_ok:
        errors.append("Honcho topology/fingerprint mismatch")

    config = json.loads((candidate / "config.fragment.json").read_text())
    model_ok = (
        config["model"].get("provider") == metadata["expected_model"].get("provider")
        and config["model"].get("default") == metadata["expected_model"].get("model")
    )
    if not model_ok:
        errors.append("model/provider mismatch")

    skill_root = candidate / "skills" / "study"
    packages = sorted(path for path in skill_root.iterdir() if path.is_dir())
    expected_skills = [item["name"] for item in metadata["skill_allowlist"]]
    actual_names = [path.name for path in packages]
    skill_set_ok = actual_names == sorted(expected_skills)
    package_mismatches = []
    expected_by_name = {item["name"]: item for item in metadata["skill_allowlist"]}
    for package in packages:
        expected = expected_by_name.get(package.name)
        if expected and package_digest(package) != expected.get("package_sha256"):
            package_mismatches.append(package.name)
    if not skill_set_ok:
        errors.append("skill package set mismatch")
    if package_mismatches:
        errors.append("package digest mismatch")

    command_names: dict[str, list[str]] = {}
    discord_names: dict[str, list[str]] = {}
    declaration_mismatches = []
    platform_incompatible = []
    host_platform = (
        "macos"
        if metadata["host_overlay"]["platform"].endswith("darwin")
        else "linux"
    )
    for package in packages:
        declared = declared_skill_name(package)
        if declared != package.name:
            declaration_mismatches.append(f"{package.name}!={declared}")
        platforms = declared_platforms(package)
        if platforms and host_platform not in platforms:
            platform_incompatible.append(
                f"{package.name}:{host_platform} not in {sorted(platforms)}"
            )
        slug = command_slug(declared)
        command_names.setdefault(slug, []).append(declared)
        discord_names.setdefault(slug[:32], []).append(declared)
    collisions = {
        "slash": {key: value for key, value in command_names.items() if len(value) > 1},
        "discord": {key: value for key, value in discord_names.items() if len(value) > 1},
    }
    collisions = {key: value for key, value in collisions.items() if value}
    if collisions:
        errors.append("normalized skill command collision")
    if declaration_mismatches:
        errors.append("skill directory/frontmatter mismatch")
    if platform_incompatible:
        errors.append("platform-incompatible skill package")
    skills_ok = (
        skill_set_ok
        and not package_mismatches
        and not collisions
        and not declaration_mismatches
        and not platform_incompatible
        and not secret_hits
    )

    runtime_actual = json.loads((candidate / "runtime-identity.json").read_text())
    runtime_expected = metadata["runtime_identity"]
    runtime_revision_match = (
        runtime_actual.get("hermes_version") == runtime_expected.get("hermes_version")
        and runtime_actual.get("source_revision") == runtime_expected.get("source_revision")
    )
    plugin_set_match = runtime_actual.get("enabled_plugins") == runtime_expected.get(
        "enabled_plugins"
    )
    if not runtime_revision_match:
        errors.append("runtime revision drift")
    if not plugin_set_match:
        errors.append("plugin-set drift")

    embedded_contract = json.loads((candidate / "registry-contract.json").read_text())
    contract_internal_match = embedded_contract == metadata["registry_contract"]
    external_contract_match = True
    if registry_path is not None:
        try:
            external_contract_match = registry_contract(registry_path) == embedded_contract
        except (OSError, KeyError, TypeError, json.JSONDecodeError):
            external_contract_match = False
    registry_ok = contract_internal_match and external_contract_match
    if not registry_ok:
        errors.append("registry/candidate contract drift")

    overlay = metadata["host_overlay"]
    undeclared_overlay = sorted(
        set(overlay)
        - set(metadata["overlay_allowlist"])
        - {"schema_version", "overlay_allowlist"}
    )
    if undeclared_overlay:
        errors.append("undeclared overlay field")

    repos = {}
    for name, configured in overlay["repository_paths"].items():
        repos[name] = (
            git_probe(Path(configured))
            if probe_live
            else {"path": configured, "status": "not-probed-candidate-only"}
        )
    if dotfiles_repo:
        repos["dotfiles"] = git_probe(dotfiles_repo)
    configured_repo_reports = [repos[name] for name in overlay["repository_paths"]]
    repositories_ready = probe_live and all(
        item.get("status") == "ok" and item.get("clean") is True
        for item in configured_repo_reports
    )
    canonical_status = (
        "fail"
        if forbidden_hits
        else ("pass" if repositories_ready else ("blocked" if probe_live else "candidate-only"))
    )

    topology_evidence = None
    external_test = "prepared-not-run"
    semantic_topology_ready = topology_ok
    if topology_report:
        topology_evidence = json.loads(topology_report.read_text(encoding="utf-8"))
        checks = topology_evidence.get("authoritative_checks", {})
        observer_visible = checks.get(
            "watari_observer_sees_lawliet_user_conclusion"
        )
        user_self_visible = checks.get(
            "shared_user_self_scope_visible_from_watari"
        )
        ai_scopes_isolated = (
            checks.get("lawliet_ai_attribution_isolated") is True
            and checks.get("watari_ai_attribution_isolated") is True
        )
        cleaned = topology_evidence.get("cleanup", {}).get("workspace_deleted") is True
        if (
            observer_visible is False
            and user_self_visible is True
            and ai_scopes_isolated
            and cleaned
        ):
            external_test = "pass-user-self-shared-ai-scopes-isolated-cleaned"
        else:
            external_test = "invalid-or-cleanup-unverified"
            semantic_topology_ready = False

    credential_present = bool(os.getenv("HONCHO_API_KEY")) or (
        topology_evidence is not None
        and topology_evidence.get("secret_readiness", {}).get("HONCHO_API_KEY")
        == "present"
    )
    fixture = json.loads((candidate / "behavior-fixture.json").read_text())
    fixture_cases = fixture.get("cases", [])
    behavior_ready = bool(fixture_cases) and all(
        case.get("automatic") and case.get("severity") in {"P0", "P1"}
        for case in fixture_cases
    )
    static_ok = (
        effective_match
        and model_ok
        and not undeclared_overlay
    )
    report = {
        "schema_version": 2,
        "host": overlay["host"],
        "canonical_content": {
            "status": canonical_status,
            "repositories": repos,
            "repositories_ready": repositories_ready,
            "ladr_artifacts": overlay["ladr_artifacts"],
            "forbidden_sync_hits": forbidden_hits,
        },
        "static_policy": {
            "status": "pass" if static_ok else "fail",
            "bundle_aggregate_sha256": metadata["bundle_aggregate_sha256"],
            "effective_file_digests": metadata["effective_file_digests"],
            "model_provider_match": model_ok,
            "undeclared_overlay_fields": undeclared_overlay,
        },
        "skill_provenance": {
            "status": "pass" if skills_ok else "fail",
            "selected_skills": metadata["skill_allowlist"],
            "actual_packages": actual_names,
            "package_digest_mismatches": package_mismatches,
            "command_collisions": collisions,
            "declaration_mismatches": declaration_mismatches,
            "platform_incompatible": platform_incompatible,
            "probable_secret_paths": secret_hits,
        },
        "runtime_identity": {
            "status": "pass" if runtime_revision_match else "fail",
            "expected_hermes_version": runtime_expected.get("hermes_version"),
            "actual_hermes_version": runtime_actual.get("hermes_version"),
            "expected_source_revision": runtime_expected.get("source_revision"),
            "actual_source_revision": runtime_actual.get("source_revision"),
        },
        "plugin_identity": {
            "status": "pass" if plugin_set_match else "fail",
            "expected_enabled_plugins": runtime_expected.get("enabled_plugins"),
            "actual_enabled_plugins": runtime_actual.get("enabled_plugins"),
        },
        "registry_consistency": {
            "status": "pass" if registry_ok else "fail",
            "embedded_contract_match": contract_internal_match,
            "external_registry_match": external_contract_match,
            "semantic_memory_readiness": embedded_contract.get(
                "semantic_memory_readiness"
            ),
        },
        "semantic_memory_readiness": {
            "status": (
                "ready"
                if semantic_topology_ready
                and credential_present
                and embedded_contract.get("semantic_memory_readiness") != "blocked"
                else "blocked"
            ),
            "topology_match": topology_ok,
            "observer_scope_cross_host_visible": (
                topology_evidence.get("authoritative_checks", {}).get(
                    "watari_observer_sees_lawliet_user_conclusion"
                )
                if topology_evidence is not None
                else None
            ),
            "shared_user_self_scope_cross_host_visible": (
                topology_evidence.get("authoritative_checks", {}).get(
                    "shared_user_self_scope_visible_from_watari"
                )
                if topology_evidence is not None
                else None
            ),
            "host_specific_ai_scopes_isolated": (
                topology_evidence.get("authoritative_checks", {}).get(
                    "lawliet_ai_attribution_isolated"
                ) is True
                and topology_evidence.get("authoritative_checks", {}).get(
                    "watari_ai_attribution_isolated"
                ) is True
                if topology_evidence is not None
                else None
            ),
            "shared_durable_scope": hmeta["shared_durable_scope"],
            "observer_inference_scope": hmeta["observer_inference_scope"],
            "workspace_user_peer_fingerprint": hmeta["user_peer_fingerprint"],
            "ai_peer_fingerprint": hmeta["ai_peer_fingerprint"],
            "distinct_ai_peers": hmeta["expected_distinct_ai_peers"],
            "HONCHO_API_KEY": "present" if credential_present else "missing",
            "external_test": external_test,
        },
        "behavior_test": {
            "status": "prepared-not-run" if behavior_ready else "fail",
            "fixture_version": fixture.get("fixture_version"),
            "fixture_cases": [case["id"] for case in fixture_cases],
            "activation_required": True,
            "behavioral_compliance_claim": "not-run",
        },
        "errors": errors,
    }
    return report, not errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--probe-live", action="store_true")
    parser.add_argument("--dotfiles-repo", type=Path)
    parser.add_argument("--topology-report", type=Path)
    parser.add_argument("--registry", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report, ok = check_candidate(
        args.candidate.resolve(),
        args.probe_live,
        args.dotfiles_repo.resolve() if args.dotfiles_repo else None,
        args.topology_report.resolve() if args.topology_report else None,
        args.registry.resolve() if args.registry else None,
    )
    text = json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
