#!/usr/bin/env python3
"""Validate the default profile's non-secret cross-host continuity contract."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Final

NODE_ROSTER: Final = ("lawliet", "watari")
WRITER_CLAIMS: Final = frozenset(
    {"gateway_writer", "scheduler_writer", "control_plane_writer"}
)
CONTRACT_KEYS: Final = frozenset(
    {
        "schema_version",
        "profile",
        "semantic_identity",
        "shared_memory",
        "host_local_state",
        "session_continuity",
        "control_plane_authority",
        "nodes",
    }
)
IDENTITY_KEYS: Final = frozenset({"honcho_host", "workspace", "user_peer", "ai_peer"})
CONTINUITY_IDENTITY_KEYS: Final = frozenset({"workspace", "user_peer", "ai_peer"})
SHARED_MEMORY_KEYS: Final = frozenset({"allowed", "scope"})
SESSION_KEYS: Final = frozenset(
    {"mechanism", "implementation", "sources", "transport_readiness"}
)
SESSION_POLICY: Final = {
    "mechanism": "existing-source-authoritative-archive",
    "implementation": "not-reimplemented-by-this-candidate",
    "sources": list(NODE_ROSTER),
    "transport_readiness": "blocked-pending-separate-device-reconciliation",
}
CONTRACT_NODE_KEYS: Final = frozenset({"system", "roles"}) | WRITER_CLAIMS
REGISTRY_NODE_KEYS: Final = frozenset(
    {"system", "default_profile_roles", "default_profile_claims"}
)
CONTINUITY_KEYS: Final = frozenset(
    {"contract_version", "nodes", "semantic_identity", "session_continuity"}
)
REQUIRED_LOCAL_STATE: Final = frozenset(
    {
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
)
MAX_REASONS: Final = 32


def _reason(errors: list[str], code: str) -> None:
    """Append one bounded, non-secret reason code."""
    if code not in errors and len(errors) < MAX_REASONS:
        errors.append(code)


def effective_honcho_identity(config: object, host_key: str) -> dict[str, object]:
    """Return only the identity fields used by the Honcho plugin."""
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


def _contract_identity(contract: dict[object, object]) -> dict[str, object]:
    identity = contract.get("semantic_identity")
    if not isinstance(identity, dict):
        return {}
    return {
        "workspace": identity.get("workspace"),
        "user_peer": identity.get("user_peer"),
        "ai_peer": identity.get("ai_peer"),
    }


def _exact_keys(value: object, expected: frozenset[str]) -> bool:
    return isinstance(value, dict) and set(value) == expected


def _writer_ownership_valid(nodes: object, authority: str) -> bool:
    if not isinstance(nodes, dict):
        return False
    for claim in WRITER_CLAIMS:
        owners = [
            name
            for name, spec in nodes.items()
            if isinstance(spec, dict) and spec.get(claim) is True
        ]
        if owners != [authority]:
            return False
    return True


def validate(contract: object, registry: object, honcho: object) -> list[str]:
    """Return only fixed reason codes; never include input values or paths."""
    errors: list[str] = []
    if not isinstance(contract, dict):
        return ["CONTRACT_ROOT_INVALID"]
    if not isinstance(registry, dict):
        return ["REGISTRY_ROOT_INVALID"]

    if set(contract) != CONTRACT_KEYS:
        _reason(errors, "CONTRACT_SCHEMA_INVALID")
    if (
        type(contract.get("schema_version")) is not int
        or contract.get("schema_version") != 1
        or contract.get("profile") != "default"
    ):
        _reason(errors, "CONTRACT_HEADER_INVALID")

    identity_spec = contract.get("semantic_identity")
    expected_identity = _contract_identity(contract)
    if (
        not _exact_keys(identity_spec, IDENTITY_KEYS)
        or not isinstance(identity_spec.get("honcho_host"), str)
        or identity_spec.get("honcho_host") != "hermes"
        or any(
            not isinstance(value, str) or not value
            for value in expected_identity.values()
        )
    ):
        _reason(errors, "CONTRACT_IDENTITY_INVALID")
    honcho_host = (
        identity_spec.get("honcho_host") if isinstance(identity_spec, dict) else ""
    )
    actual_identity = effective_honcho_identity(
        honcho, honcho_host if isinstance(honcho_host, str) else ""
    )
    if actual_identity != expected_identity:
        _reason(errors, "HONCHO_IDENTITY_DRIFT")

    authority = contract.get("control_plane_authority")
    if authority != "lawliet":
        _reason(errors, "CONTRACT_AUTHORITY_INVALID")
    contract_nodes = contract.get("nodes")
    contract_nodes_valid = (
        isinstance(contract_nodes, dict)
        and tuple(contract_nodes) == NODE_ROSTER
        and all(
            _exact_keys(contract_nodes.get(name), CONTRACT_NODE_KEYS)
            and isinstance(contract_nodes[name].get("system"), str)
            and isinstance(contract_nodes[name].get("roles"), list)
            and all(
                isinstance(role, str) for role in contract_nodes[name].get("roles", [])
            )
            and all(
                type(contract_nodes[name].get(claim)) is bool for claim in WRITER_CLAIMS
            )
            for name in NODE_ROSTER
        )
    )
    if not contract_nodes_valid:
        _reason(errors, "CONTRACT_NODES_INVALID")
    if not _writer_ownership_valid(contract_nodes, "lawliet"):
        _reason(errors, "CONTRACT_WRITER_OWNERSHIP_INVALID")

    session = contract.get("session_continuity")
    if not _exact_keys(session, SESSION_KEYS) or session != SESSION_POLICY:
        _reason(errors, "CONTRACT_SESSION_POLICY_INVALID")

    profiles = registry.get("profiles")
    default = profiles.get("default") if isinstance(profiles, dict) else None
    continuity = (
        default.get("cross_host_continuity") if isinstance(default, dict) else None
    )
    if not _exact_keys(continuity, CONTINUITY_KEYS):
        _reason(errors, "REGISTRY_CONTINUITY_SCHEMA_INVALID")
    else:
        registry_identity = continuity.get("semantic_identity")
        if (
            not _exact_keys(registry_identity, CONTINUITY_IDENTITY_KEYS)
            or registry_identity != expected_identity
        ):
            _reason(errors, "REGISTRY_IDENTITY_DRIFT")
        if (
            type(continuity.get("contract_version")) is not int
            or continuity.get("contract_version") != 1
        ):
            _reason(errors, "REGISTRY_CONTRACT_VERSION_DRIFT")
        if continuity.get("nodes") != list(NODE_ROSTER):
            _reason(errors, "REGISTRY_CONTINUITY_ROSTER_DRIFT")
        if continuity.get("session_continuity") != SESSION_POLICY:
            _reason(errors, "REGISTRY_SESSION_POLICY_DRIFT")

    workspace = expected_identity.get("workspace")
    if not isinstance(default, dict) or default.get("memory_workspace") != workspace:
        _reason(errors, "REGISTRY_DEFAULT_WORKSPACE_DRIFT")
    if registry.get("control_plane") != "default":
        _reason(errors, "REGISTRY_CONTROL_PLANE_DRIFT")
    exchange = registry.get("information_exchange")
    semantic = exchange.get("semantic_memory") if isinstance(exchange, dict) else None
    if (
        not isinstance(semantic, dict)
        or semantic.get("general_shared_workspace") != workspace
    ):
        _reason(errors, "REGISTRY_SHARED_WORKSPACE_DRIFT")

    registry_nodes = registry.get("nodes")
    claim_nodes: dict[str, object] = {}
    registry_nodes_valid = (
        isinstance(registry_nodes, dict) and tuple(registry_nodes) == NODE_ROSTER
    )
    if not registry_nodes_valid:
        _reason(errors, "REGISTRY_NODE_ROSTER_INVALID")
    if isinstance(registry_nodes, dict):
        for name in NODE_ROSTER:
            spec = registry_nodes.get(name)
            contract_spec = (
                contract_nodes.get(name) if isinstance(contract_nodes, dict) else None
            )
            if not _exact_keys(spec, REGISTRY_NODE_KEYS):
                _reason(errors, "REGISTRY_NODE_SCHEMA_INVALID")
                continue
            claims = spec.get("default_profile_claims")
            claim_nodes[name] = claims
            if not _exact_keys(claims, WRITER_CLAIMS) or any(
                type(claims.get(claim)) is not bool for claim in WRITER_CLAIMS
            ):
                _reason(errors, "REGISTRY_WRITER_CLAIMS_INVALID")
                continue
            if not isinstance(contract_spec, dict):
                _reason(errors, "REGISTRY_NODE_CONTRACT_DRIFT")
                continue
            if (
                spec.get("system") != contract_spec.get("system")
                or spec.get("default_profile_roles") != contract_spec.get("roles")
                or any(
                    claims.get(claim) is not contract_spec.get(claim)
                    for claim in WRITER_CLAIMS
                )
            ):
                _reason(errors, "REGISTRY_NODE_CONTRACT_DRIFT")
    if not _writer_ownership_valid(claim_nodes, "lawliet"):
        _reason(errors, "REGISTRY_WRITER_OWNERSHIP_INVALID")

    local_state = contract.get("host_local_state")
    if (
        not isinstance(local_state, list)
        or not all(isinstance(item, str) for item in local_state)
        or set(local_state) != REQUIRED_LOCAL_STATE
        or len(local_state) != len(REQUIRED_LOCAL_STATE)
    ):
        _reason(errors, "CONTRACT_HOST_LOCAL_STATE_INVALID")

    shared_memory = contract.get("shared_memory")
    registry_allowed = (
        semantic.get("allowed_content") if isinstance(semantic, dict) else None
    )
    if (
        not _exact_keys(shared_memory, SHARED_MEMORY_KEYS)
        or shared_memory.get("scope") != "ordinary-only"
        or not isinstance(shared_memory.get("allowed"), list)
        or shared_memory.get("allowed") != registry_allowed
    ):
        _reason(errors, "SHARED_MEMORY_POLICY_DRIFT")

    return errors


class DuplicateKeyError(ValueError):
    """Raised for any duplicate JSON object key."""


def _reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError
        result[key] = value
    return result


def _load_json(path: Path) -> object:
    text = path.read_bytes().decode("utf-8")
    return json.loads(text, object_pairs_hook=_reject_duplicate_keys)


def validate_paths(
    contract_path: Path, registry_path: Path, honcho_path: Path
) -> list[str]:
    loaded: list[object] = []
    for code, path in (
        ("CONTRACT_LOAD_REFUSED", contract_path),
        ("REGISTRY_LOAD_REFUSED", registry_path),
        ("HONCHO_LOAD_REFUSED", honcho_path),
    ):
        try:
            loaded.append(_load_json(path))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, DuplicateKeyError):
            return [code]
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
