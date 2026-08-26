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


def build(host: str, output: Path) -> None:
    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
    verify_manifest(manifest)
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
                }
            },
        }
        shutil.copy2(ROOT / "SOUL.md", temp / "SOUL.md")
        shutil.copy2(ROOT / "behavior-fixture.json", temp / "behavior-fixture.json")
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
            "effective_file_digests": effective,
            "honcho": {
                "workspace": honcho_identity["workspace"],
                "user_peer": honcho_identity["user_peer"],
                "user_peer_fingerprint": fingerprint(honcho_identity["workspace"], honcho_identity["user_peer"]),
                "ai_peer": overlay["ai_peer"],
                "ai_peer_fingerprint": fingerprint(honcho_identity["workspace"], overlay["ai_peer"]),
                "expected_distinct_ai_peers": honcho_identity["ai_peers"],
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
