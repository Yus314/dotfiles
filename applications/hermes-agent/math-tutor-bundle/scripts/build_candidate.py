#!/usr/bin/env python3
"""Build a host-specific, non-activated math profile candidate."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = [
    "state.db", "state.db-wal", "state.db-shm", "sessions", "logs", "cache",
    "caches", "auth.json", ".env", "credentials", "oauth", "cron", "gateway",
    "processes.json", "gateway_state.json", "*.lock",
]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fingerprint(*parts: str) -> str:
    return hashlib.sha256("\0".join(parts).encode()).hexdigest()


def verify_manifest(manifest: dict) -> None:
    failures = []
    for rel, expected in manifest["content_digests"].items():
        path = ROOT / rel
        actual = digest(path) if path.is_file() else "missing"
        if actual != expected:
            failures.append(f"{rel}: expected {expected}, got {actual}")
    if failures:
        raise SystemExit("manifest verification failed:\n" + "\n".join(failures))


def substitute(value, replacements: dict[str, str]):
    if isinstance(value, str):
        for old, new in replacements.items():
            value = value.replace(old, new)
        return value
    if isinstance(value, list):
        return [substitute(item, replacements) for item in value]
    if isinstance(value, dict):
        return {key: substitute(item, replacements) for key, item in value.items()}
    return value


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")


def registry_contract(manifest: dict) -> dict:
    registry_path = ROOT.parent / "profile-registry.json"
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    math = registry["profiles"]["math"]
    parity = math.get("parity_candidate")
    if not isinstance(parity, dict):
        raise SystemExit("math registry is missing parity_candidate contract")
    expected_skills = [item["name"] for item in manifest["skill_allowlist"]]
    if parity.get("skill_packages") != expected_skills:
        raise SystemExit("math registry skill package contract mismatch")
    expected_runtime = {
        key: manifest["runtime_identity"][key]
        for key in ("hermes_version", "source_revision", "enabled_plugins")
    }
    if parity.get("runtime_identity") != expected_runtime:
        raise SystemExit("math registry runtime identity contract mismatch")
    if parity.get("memory_workspace") != manifest["honcho"]["workspace"]:
        raise SystemExit("math registry candidate memory workspace mismatch")
    if parity.get("semantic_memory_readiness") != "approved-presence-gated":
        raise SystemExit("math registry semantic memory must be approved and presence-gated")
    continuity = parity.get("continuity_policy")
    expected_continuity = {
        "shared_durable_scope": manifest["honcho"]["shared_durable_scope"],
        "observer_inference_scope": manifest["honcho"]["observer_inference_scope"],
        "ai_peers": manifest["honcho"]["ai_peers"],
    }
    if continuity != expected_continuity:
        raise SystemExit("math registry continuity policy mismatch")
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


def build(host: str, output: Path) -> None:
    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    verify_manifest(manifest)
    profile_contract = registry_contract(manifest)
    overlay = json.loads((ROOT / "overlays" / f"{host}.json").read_text(encoding="utf-8"))
    declared_overlay_keys = set(overlay["overlay_allowlist"]) | {"schema_version", "overlay_allowlist"}
    if set(overlay) != declared_overlay_keys:
        raise SystemExit("overlay contains undeclared keys")
    if overlay["host"] != host:
        raise SystemExit("overlay host mismatch")

    parent = output.parent.resolve()
    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{host}-candidate-", dir=parent) as temp_name:
        temp = Path(temp_name)
        profile_home = f"{overlay['home']}/.hermes/profiles/math"
        replacements = {
            "${PROFILE_HOME}": profile_home,
            "${MATH_STUDY_ROOT}": overlay["repository_paths"]["study_log"] + "/math",
        }
        config = substitute(json.loads((ROOT / "config-fragment.json").read_text()), replacements)
        honcho_identity = manifest["honcho"]
        honcho = {
            "workspace": honcho_identity["workspace"],
            "peerName": honcho_identity["user_peer"],
            "continuityPolicy": {
                "sharedDurableScope": honcho_identity["shared_durable_scope"],
                "observerInferenceScope": honcho_identity["observer_inference_scope"],
                "promotion": "explicit-reviewed-only",
            },
            "hosts": {
                "hermes_math": {
                    "enabled": True,
                    "workspace": honcho_identity["workspace"],
                    "peerName": honcho_identity["user_peer"],
                    "aiPeer": overlay["ai_peer"],
                    "recallMode": "hybrid",
                    "writeFrequency": "async",
                    "sessionStrategy": "per-directory",
                    "saveMessages": True,
                    "pinUserPeer": False,
                    "runtimePeerPrefix": "gateway_",
                    "userPeerAliases": {"885083579367972874": honcho_identity["user_peer"]},
                    "observation": {
                        "user": {"observeMe": True, "observeOthers": False},
                        "ai": {"observeMe": True, "observeOthers": False},
                    },
                }
            },
        }
        shutil.copy2(ROOT / "SOUL.md", temp / "SOUL.md")
        shutil.copy2(ROOT / "behavior-fixture.json", temp / "behavior-fixture.json")
        shutil.copy2(ROOT / "runtime-identity.json", temp / "runtime-identity.json")
        write_json(temp / "registry-contract.json", profile_contract)
        write_json(temp / "config.fragment.json", config)
        write_json(temp / "honcho.json", honcho)
        for skill in manifest["skill_allowlist"]:
            shutil.copytree(ROOT / skill["source"], temp / "skills" / "study" / skill["name"])

        effective = {}
        for path in sorted(temp.rglob("*")):
            if path.is_file():
                effective[path.relative_to(temp).as_posix()] = digest(path)
        metadata = {
            "schema_version": 1,
            "bundle_version": manifest["bundle_version"],
            "bundle_aggregate_sha256": manifest["aggregate_sha256"],
            "host_overlay": overlay,
            "overlay_allowlist": overlay["overlay_allowlist"],
            "expected_model": manifest["expected_model"],
            "skill_allowlist": manifest["skill_allowlist"],
            "runtime_identity": manifest["runtime_identity"],
            "registry_contract": profile_contract,
            "effective_file_digests": effective,
            "honcho": {
                "workspace": honcho_identity["workspace"],
                "user_peer": honcho_identity["user_peer"],
                "user_peer_fingerprint": fingerprint(honcho_identity["workspace"], honcho_identity["user_peer"]),
                "ai_peer": overlay["ai_peer"],
                "ai_peer_fingerprint": fingerprint(honcho_identity["workspace"], overlay["ai_peer"]),
                "expected_distinct_ai_peers": honcho_identity["ai_peers"],
                "shared_durable_scope": honcho_identity["shared_durable_scope"],
                "observer_inference_scope": honcho_identity["observer_inference_scope"],
            },
            "secret_requirements": {"HONCHO_API_KEY": "presence-only"},
        }
        write_json(temp / "candidate-metadata.json", metadata)
        write_json(temp / "sync-inputs.json", {
            "schema_version": 1,
            "allowed_candidate_paths": sorted(effective),
            "forbidden_path_patterns": FORBIDDEN,
            "operational_state_is_host_local": True,
        })
        if output.exists():
            shutil.rmtree(output)
        shutil.move(str(temp), output)
    print(f"built host={host} output={output} bundle={manifest['aggregate_sha256']}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", choices=["lawliet", "watari"], required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    build(args.host, args.output.resolve())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
