#!/usr/bin/env python3
"""Validate the default profile's non-secret cross-host continuity contract."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


WRITER_CLAIMS = ("gateway_writer", "scheduler_writer", "control_plane_writer")


def effective_honcho_identity(config: object, host_key: str) -> dict[str, object]:
    """Return only the non-secret identity fields used by the Honcho plugin."""
    if not isinstance(config, dict):
        config = {}
    hosts = config.get("hosts")
    host = hosts.get(host_key) if isinstance(hosts, dict) else None
    if not isinstance(host, dict):
        host = {}
    return {
        "workspace": host.get("workspace") or config.get("workspace"),
        "user_peer": host.get("peerName") or config.get("peerName"),
        "ai_peer": host.get("aiPeer") or config.get("aiPeer"),
    }


def _contract_identity(contract: dict) -> dict[str, object]:
    identity = contract.get("semantic_identity")
    if not isinstance(identity, dict):
        return {}
    return {
        "workspace": identity.get("workspace"),
        "user_peer": identity.get("user_peer"),
        "ai_peer": identity.get("ai_peer"),
    }


def _writer_errors(prefix: str, nodes: object, authority: object) -> list[str]:
    errors: list[str] = []
    if not isinstance(nodes, dict):
        return [f"{prefix} nodes must be an object"]
    for claim in WRITER_CLAIMS:
        owners = sorted(
            name
            for name, spec in nodes.items()
            if isinstance(spec, dict) and spec.get(claim) is True
        )
        if owners != [authority]:
            errors.append(
                f"{prefix} {claim} must have exactly one owner: "
                f"expected={[authority]} actual={owners}"
            )
    return errors


def validate(contract: object, registry: object, honcho: object) -> list[str]:
    errors: list[str] = []
    if not isinstance(contract, dict):
        return ["continuity contract must be an object"]
    if not isinstance(registry, dict):
        return ["profile registry must be an object"]

    if contract.get("schema_version") != 1 or contract.get("profile") != "default":
        errors.append(
            "continuity contract must be schema version 1 for profile default"
        )

    expected_identity = _contract_identity(contract)
    if any(
        not isinstance(value, str) or not value for value in expected_identity.values()
    ):
        errors.append(
            "contract semantic identity must contain non-empty workspace/user/AI peers"
        )
    identity_spec = contract.get("semantic_identity")
    honcho_host = (
        identity_spec.get("honcho_host") if isinstance(identity_spec, dict) else None
    )
    actual_identity = effective_honcho_identity(honcho, str(honcho_host or ""))
    for field, expected in expected_identity.items():
        actual = actual_identity[field]
        if actual != expected:
            errors.append(
                f"effective Honcho {field} drift: expected={expected!r} actual={actual!r}"
            )

    authority = contract.get("control_plane_authority")
    contract_nodes = contract.get("nodes")
    if authority != "lawliet":
        errors.append("contract control-plane authority must be lawliet")
    errors.extend(_writer_errors("contract", contract_nodes, authority))

    profiles = registry.get("profiles")
    default = profiles.get("default") if isinstance(profiles, dict) else None
    continuity = (
        default.get("cross_host_continuity") if isinstance(default, dict) else None
    )
    if not isinstance(continuity, dict):
        errors.append("registry default profile must declare cross_host_continuity")
    else:
        registry_identity = continuity.get("semantic_identity")
        if registry_identity != expected_identity:
            errors.append(
                "registry semantic identity must match the continuity contract"
            )
        if continuity.get("contract_version") != contract.get("schema_version"):
            errors.append("registry continuity contract version drift")
        expected_nodes = (
            sorted(contract_nodes) if isinstance(contract_nodes, dict) else []
        )
        if continuity.get("nodes") != expected_nodes:
            errors.append("registry continuity node roster drift")
        session = contract.get("session_continuity")
        mechanism = session.get("mechanism") if isinstance(session, dict) else None
        if continuity.get("session_continuity") != mechanism:
            errors.append("registry session continuity policy drift")

    registry_nodes = registry.get("nodes")
    claim_nodes: dict[str, object] = {}
    if not isinstance(registry_nodes, dict):
        errors.append("registry nodes must be an object")
    else:
        expected_node_names = (
            set(contract_nodes) if isinstance(contract_nodes, dict) else set()
        )
        if set(registry_nodes) != expected_node_names:
            errors.append(
                "registry node roster must exactly match the continuity contract"
            )
        for name, spec in registry_nodes.items():
            claims = (
                spec.get("default_profile_claims") if isinstance(spec, dict) else None
            )
            claim_nodes[name] = claims
            contract_spec = (
                contract_nodes.get(name) if isinstance(contract_nodes, dict) else None
            )
            if not isinstance(claims, dict) or not isinstance(contract_spec, dict):
                errors.append(
                    f"registry node {name!r} has invalid default profile claims"
                )
                continue
            if spec.get("system") != contract_spec.get("system"):
                errors.append(f"registry node {name!r} system differs from contract")
            if spec.get("default_profile_roles") != contract_spec.get("roles"):
                errors.append(f"registry node {name!r} roles differ from contract")
            for claim in WRITER_CLAIMS:
                if claims.get(claim) is not contract_spec.get(claim):
                    errors.append(
                        f"registry node {name!r} {claim} differs from contract"
                    )
    errors.extend(_writer_errors("registry", claim_nodes, authority))

    required_local = {
        "state.db",
        "state.db-wal",
        "state.db-shm",
        "routing",
        "queues",
        "cron-runtime",
        "auth",
        ".env",
        "secrets",
        "logs",
        "caches",
    }
    local_state = contract.get("host_local_state")
    if not isinstance(local_state, list) or not required_local <= set(local_state):
        errors.append("contract host-local state exclusions are incomplete")

    shared_memory = contract.get("shared_memory")
    exchange = registry.get("information_exchange")
    semantic = exchange.get("semantic_memory") if isinstance(exchange, dict) else None
    registry_allowed = (
        semantic.get("allowed_content") if isinstance(semantic, dict) else None
    )
    if (
        not isinstance(shared_memory, dict)
        or shared_memory.get("scope") != "ordinary-only"
        or shared_memory.get("allowed") != registry_allowed
    ):
        errors.append("shared-memory allowlist must match the ordinary registry policy")

    return errors


def validate_paths(
    contract_path: Path, registry_path: Path, honcho_path: Path
) -> list[str]:
    loaded: list[object] = []
    for label, path in (
        ("continuity contract", contract_path),
        ("profile registry", registry_path),
        ("Honcho config", honcho_path),
    ):
        try:
            loaded.append(json.loads(path.read_text()))
        except (OSError, json.JSONDecodeError):
            return [f"missing or invalid {label}: {path}"]
    return validate(*loaded)


def main() -> int:
    source_root = Path(__file__).parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--contract",
        type=Path,
        default=source_root / "default-continuity-contract-v1.json",
    )
    parser.add_argument(
        "--registry", type=Path, default=source_root / "profile-registry.json"
    )
    parser.add_argument(
        "--honcho", type=Path, default=Path.home() / ".hermes/honcho.json"
    )
    args = parser.parse_args()
    errors = validate_paths(args.contract, args.registry, args.honcho)
    if errors:
        print("DEFAULT_CONTINUITY_INVALID")
        for error in errors:
            print(f"- {error}")
        return 1
    print("DEFAULT_CONTINUITY_OK profile=default nodes=lawliet,watari")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
