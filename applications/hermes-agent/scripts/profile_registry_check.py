#!/usr/bin/env python3
"""Validate the declarative Hermes profile registry against live profile state."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Callable

import yaml


ALLOWED_SHARED_SKILL_GROUPS = {
    "common",
    "study",
    "engineering",
    "orchestration",
    "profile-ops",
    "usage-ops",
}
ALLOWED_SUMMARY_POLICIES = {
    "none",
    "active-weekly",
    "on-demand",
    "source-health-only",
    "blocked",
}
ALLOWED_MEMORY_SHARING_CLASSES = {
    "general-shared",
    "sensitive-isolated",
    "profile-local",
    "disabled",
}
REQUIRED_HANDOFF_FIELDS = {
    "schema_family",
    "schema_version",
    "handoff_id",
    "source_profile",
    "target_profiles",
    "purpose",
    "generated_at",
    "valid_until",
    "scope",
    "status",
    "source_refs",
    "source_health",
    "sensitivity",
    "raw_data_included",
    "retention_class",
    "supersedes",
    "assumptions",
    "uncertainties",
}
OPTIONAL_HANDOFF_FIELDS = {
    "in_reply_to",
    "requested_fields",
    "returned_fields",
    "response_deadline",
    "hop_count",
    "max_hops",
}
REQUIRED_WEEKLY_SUMMARY_FIELDS = {
    "schema_family",
    "schema_version",
    "owner_profile",
    "generated_at",
    "coverage_start",
    "coverage_end",
    "source_watermark",
    "status",
}
REQUIRED_SENSITIVITY_LEVELS = {"ordinary", "sensitive", "restricted"}
REQUIRED_RETENTION_CLASSES = {"transient", "promotable", "durable"}


def _nonempty_string_list(value: object) -> bool:
    return (
        isinstance(value, list)
        and bool(value)
        and all(isinstance(item, str) and bool(item.strip()) for item in value)
    )


def _string_set(value: object) -> set[str]:
    if not isinstance(value, list):
        return set()
    return {item for item in value if isinstance(item, str) and item.strip()}


def validate_parity_candidate(name: str, spec: dict) -> list[str]:
    candidate = spec.get("parity_candidate")
    if candidate is None:
        return []
    prefix = f"{name}: parity_candidate"
    required = {
        "canonical_root",
        "summary_path",
        "skill_packages",
        "memory_workspace",
        "semantic_memory_readiness",
        "continuity_policy",
        "runtime_identity",
    }
    if not isinstance(candidate, dict) or set(candidate) != required:
        return [f"{prefix} must use the closed candidate schema"]
    errors: list[str] = []
    if candidate.get("canonical_root") not in (spec.get("canonical_paths") or []):
        errors.append(f"{prefix} canonical_root must be a declared canonical path")
    if candidate.get("summary_path") != spec.get("summary_path"):
        errors.append(f"{prefix} summary_path must match the profile summary path")
    skills = candidate.get("skill_packages")
    skill_set = _string_set(skills)
    if (
        not isinstance(skills, list)
        or len(skills) != 3
        or len(skills) != len(skill_set)
    ):
        errors.append(f"{prefix} skill_packages must contain exactly three unique names")
    workspace = candidate.get("memory_workspace")
    if not isinstance(workspace, str) or not workspace.strip():
        errors.append(f"{prefix} memory_workspace must be non-empty")
    if candidate.get("semantic_memory_readiness") != "approved-presence-gated":
        errors.append(
            f"{prefix} semantic_memory_readiness must be approved-presence-gated"
        )
    continuity = candidate.get("continuity_policy")
    if not isinstance(continuity, dict) or set(continuity) != {
        "shared_durable_scope",
        "observer_inference_scope",
        "ai_peers",
    }:
        errors.append(f"{prefix} continuity_policy must use the closed scope schema")
    else:
        if continuity.get("shared_durable_scope") != "user-self":
            errors.append(f"{prefix} shared durable scope must be user-self")
        if continuity.get("observer_inference_scope") != "host-local":
            errors.append(f"{prefix} observer inference scope must be host-local")
        ai_peers = continuity.get("ai_peers")
        if (
            not isinstance(ai_peers, list)
            or len(ai_peers) != 2
            or len(set(ai_peers)) != 2
            or any(not isinstance(peer, str) or not peer for peer in ai_peers)
        ):
            errors.append(f"{prefix} continuity_policy must declare two distinct AI peers")
    runtime = candidate.get("runtime_identity")
    if not isinstance(runtime, dict) or set(runtime) != {
        "hermes_version",
        "source_revision",
        "enabled_plugins",
    }:
        errors.append(f"{prefix} runtime_identity must use the closed identity schema")
    else:
        for field in ("hermes_version", "source_revision"):
            if not isinstance(runtime.get(field), str) or not runtime[field].strip():
                errors.append(f"{prefix} runtime_identity.{field} must be non-empty")
        plugins = runtime.get("enabled_plugins")
        if (
            not isinstance(plugins, list)
            or any(
                not isinstance(plugin, str) or not plugin.strip()
                for plugin in plugins
            )
            or len(plugins) != len(set(plugins))
        ):
            errors.append(
                f"{prefix} runtime_identity.enabled_plugins must be unique strings"
            )
    return errors


def profile_root(home: Path, name: str) -> Path:
    return home / ".hermes" if name == "default" else home / ".hermes/profiles" / name


def honcho_config_path(home: Path, root: Path) -> Path:
    """Resolve profile-local Honcho config with Hermes' default-profile fallback."""
    local = root / "honcho.json"
    if local.is_file() or root == home / ".hermes":
        return local
    return home / ".hermes/honcho.json"


def validate_information_exchange(registry: dict) -> tuple[list[str], str | None]:
    errors: list[str] = []
    exchange = registry.get("information_exchange")
    if not isinstance(exchange, dict):
        return ["registry information_exchange must be an object"], None

    semantic = exchange.get("semantic_memory")
    general_workspace: str | None = None
    if not isinstance(semantic, dict):
        errors.append("information_exchange.semantic_memory must be an object")
    else:
        value = semantic.get("general_shared_workspace")
        if isinstance(value, str) and value.strip():
            general_workspace = value
        else:
            errors.append(
                "information_exchange.semantic_memory.general_shared_workspace must be a non-empty string"
            )
        for field in ("allowed_content", "forbidden_content"):
            items = semantic.get(field)
            if not isinstance(items, list) or not items or any(
                not isinstance(item, str) or not item.strip() for item in items
            ):
                errors.append(
                    f"information_exchange.semantic_memory.{field} must be a non-empty string list"
                )

    weekly = exchange.get("weekly_summary")
    if not isinstance(weekly, dict):
        errors.append("information_exchange.weekly_summary must be an object")
    else:
        if weekly.get("schema_family") != "weekly_summary":
            errors.append(
                "information_exchange.weekly_summary schema_family must be weekly_summary"
            )
        if weekly.get("schema_version") != 1:
            errors.append("information_exchange.weekly_summary schema_version must be 1")
        fields = weekly.get("required_fields")
        field_set = _string_set(fields)
        missing = sorted(REQUIRED_WEEKLY_SUMMARY_FIELDS - field_set)
        if missing or not isinstance(fields, list) or len(fields) != len(field_set):
            errors.append(
                "information_exchange.weekly_summary required_fields "
                f"missing={missing} or contains duplicates/invalid values"
            )

    handoff = exchange.get("handoff")
    if not isinstance(handoff, dict):
        errors.append("information_exchange.handoff must be an object")
    else:
        if handoff.get("schema_family") != "cross_profile_handoff":
            errors.append(
                "information_exchange.handoff schema_family must be cross_profile_handoff"
            )
        if handoff.get("schema_version") != 2:
            errors.append("information_exchange.handoff schema_version must be 2")
        fields = handoff.get("required_fields")
        field_set = _string_set(fields)
        missing = sorted(REQUIRED_HANDOFF_FIELDS - field_set)
        if missing or not isinstance(fields, list) or len(fields) != len(field_set):
            errors.append(
                f"information_exchange.handoff required_fields missing={missing} or contains duplicates/invalid values"
            )
        optional_fields = handoff.get("optional_fields")
        optional_set = _string_set(optional_fields)
        if (
            optional_set != OPTIONAL_HANDOFF_FIELDS
            or not isinstance(optional_fields, list)
            or len(optional_fields) != len(optional_set)
        ):
            errors.append(
                "information_exchange.handoff optional_fields must exactly match consultation correlation fields"
            )
        levels = handoff.get("sensitivity_levels")
        level_set = _string_set(levels)
        if level_set != REQUIRED_SENSITIVITY_LEVELS:
            errors.append(
                "information_exchange.handoff sensitivity_levels must be ordinary, sensitive, restricted"
            )
        retention = handoff.get("retention_classes")
        retention_set = _string_set(retention)
        if retention_set != REQUIRED_RETENTION_CLASSES:
            errors.append(
                "information_exchange.handoff retention_classes must be transient, promotable, durable"
            )
        purposes = handoff.get("allowed_purposes")
        purpose_set = _string_set(purposes)
        if (
            not _nonempty_string_list(purposes)
            or not {"review-request", "consultation-response"} <= purpose_set
        ):
            errors.append(
                "information_exchange.handoff allowed_purposes must include consultation request and response"
            )
        matrix = handoff.get("destination_sensitivity")
        profiles = registry.get("profiles")
        if not isinstance(matrix, dict) or not matrix:
            errors.append(
                "information_exchange.handoff destination_sensitivity must be an object"
            )
        else:
            for destination, allowed in matrix.items():
                if not isinstance(destination, str) or not isinstance(profiles, dict) or destination not in profiles:
                    errors.append(
                        f"information_exchange.handoff destination_sensitivity has unknown profile {destination!r}"
                    )
                allowed_set = _string_set(allowed)
                if not allowed_set or not allowed_set <= REQUIRED_SENSITIVITY_LEVELS:
                    errors.append(
                        "information_exchange.handoff destination_sensitivity "
                        f"for {destination!r} must use known sensitivity levels"
                    )
        if handoff.get("raw_data_default") != "forbidden":
            errors.append(
                "information_exchange.handoff raw_data_default must be forbidden"
            )

    consultation = exchange.get("consultation")
    if not isinstance(consultation, dict):
        errors.append("information_exchange.consultation must be an object")
    else:
        if consultation.get("schema_version") != 1:
            errors.append("information_exchange.consultation schema_version must be 1")
        if consultation.get("max_hops") != 1:
            errors.append("information_exchange.consultation max_hops must be 1")
        routes = consultation.get("routes")
        profiles = registry.get("profiles")
        if not isinstance(routes, list):
            errors.append("information_exchange.consultation routes must be a list")
        else:
            seen_routes: set[tuple[str, str]] = set()
            for index, route in enumerate(routes):
                prefix = f"information_exchange.consultation.routes[{index}]"
                if not isinstance(route, dict) or set(route) != {
                    "source",
                    "target",
                    "max_ttl_hours",
                    "allowed_requested_fields",
                }:
                    errors.append(f"{prefix} must use the closed route schema")
                    continue
                source = route.get("source")
                target = route.get("target")
                if (
                    not isinstance(source, str)
                    or not isinstance(target, str)
                    or not isinstance(profiles, dict)
                    or source not in profiles
                    or target not in profiles
                    or source == target
                ):
                    errors.append(f"{prefix} has invalid source or target")
                else:
                    key = (source, target)
                    if key in seen_routes:
                        errors.append(f"{prefix} duplicates route {source}->{target}")
                    seen_routes.add(key)
                ttl = route.get("max_ttl_hours")
                if isinstance(ttl, bool) or not isinstance(ttl, int) or not 1 <= ttl <= 168:
                    errors.append(f"{prefix} max_ttl_hours must be 1..168")
                allowed_fields = route.get("allowed_requested_fields")
                allowed_set = _string_set(allowed_fields)
                if (
                    not _nonempty_string_list(allowed_fields)
                    or not isinstance(allowed_fields, list)
                    or len(allowed_fields) != len(allowed_set)
                    or any(
                        not item.replace("_", "").isalnum() or not item[0].islower()
                        for item in allowed_set
                    )
                ):
                    errors.append(f"{prefix} allowed_requested_fields is invalid")

    kanban = exchange.get("kanban")
    if (
        not isinstance(kanban, dict)
        or kanban.get("content_policy") != "redacted-work-orders-only"
    ):
        errors.append(
            "information_exchange.kanban content_policy must be redacted-work-orders-only"
        )
    return errors, general_workspace


def discovered_profiles(home: Path) -> set[str]:
    result = set()
    if (home / ".hermes/config.yaml").is_file():
        result.add("default")
    root = home / ".hermes/profiles"
    if root.is_dir():
        result.update(
            path.name
            for path in root.iterdir()
            if path.is_dir() and (path / "config.yaml").is_file()
        )
    return result


GatewayState = Callable[[str], str]


def systemd_gateway_state(profile: str) -> str:
    unit = "hermes-gateway.service" if profile == "default" else f"hermes-{profile}-gateway.service"
    result = subprocess.run(
        ["systemctl", "--user", "is-active", unit],
        check=False,
        capture_output=True,
        text=True,
    )
    return "running" if result.stdout.strip() == "active" else "stopped"


def validate(
    home: Path,
    registry_path: Path,
    gateway_state: GatewayState | None = None,
) -> list[str]:
    errors: list[str] = []
    registry = json.loads(registry_path.read_text())
    if registry.get("schema_version") != 2:
        errors.append("registry schema_version must be 2")
    profiles = registry.get("profiles")
    if not isinstance(profiles, dict):
        return [*errors, "registry profiles must be an object"]

    exchange_errors, general_shared_workspace = validate_information_exchange(registry)
    errors.extend(exchange_errors)

    actual = discovered_profiles(home)
    expected = set(profiles)
    control_plane = registry.get("control_plane")
    if control_plane not in expected:
        errors.append(f"control_plane references unknown profile: {control_plane}")
    if actual != expected:
        errors.append(
            f"profile roster drift: missing={sorted(expected-actual)} unexpected={sorted(actual-expected)}"
        )

    sensitive_workspace_owners: dict[str, str] = {}
    for name, spec in sorted(profiles.items()):
        if not isinstance(spec, dict):
            errors.append(f"{name}: registry entry is not an object")
            continue
        errors.extend(validate_parity_candidate(name, spec))
        root = profile_root(home, name)
        config_path = root / "config.yaml"
        if not config_path.is_file():
            continue
        config = yaml.safe_load(config_path.read_text()) or {}
        profile_meta = yaml.safe_load((root / "profile.yaml").read_text()) if (root / "profile.yaml").is_file() else {}
        if not isinstance(profile_meta, dict) or not str(profile_meta.get("description", "")).strip():
            errors.append(f"{name}: missing profile description")
        if not (root / "SOUL.md").is_file():
            errors.append(f"{name}: missing SOUL.md")

        expected_groups = spec.get("shared_skill_groups", [])
        if not isinstance(expected_groups, list) or any(
            not isinstance(group, str) for group in expected_groups
        ):
            errors.append(f"{name}: shared_skill_groups must be a string list")
            expected_groups = []
        elif len(expected_groups) != len(set(expected_groups)):
            errors.append(f"{name}: duplicate shared skill groups: {expected_groups}")
        unknown_groups = sorted(set(expected_groups) - ALLOWED_SHARED_SKILL_GROUPS)
        if unknown_groups:
            errors.append(f"{name}: unknown shared skill groups: {unknown_groups}")
        external_dirs = ((config.get("skills") or {}).get("external_dirs") or [])
        shared_root = home / ".local/share/hermes/shared-skills"
        managed_groups = []
        for item in external_dirs:
            if not isinstance(item, str):
                continue
            expanded = Path(os.path.expandvars(os.path.expanduser(item)))
            if not expanded.is_absolute():
                expanded = root / expanded
            if expanded.parent == shared_root:
                managed_groups.append(expanded.name)
        if managed_groups != expected_groups:
            errors.append(
                f"{name}: shared skill groups drift: expected={expected_groups} actual={managed_groups}"
            )

        kanban = config.get("kanban") or {}
        expected_dispatch = name == control_plane
        for key in ("dispatch_in_gateway", "auto_decompose"):
            actual_value = kanban.get(key) if isinstance(kanban, dict) else None
            if actual_value is not expected_dispatch:
                errors.append(
                    f"{name}: kanban.{key} drift: "
                    f"expected={expected_dispatch} actual={actual_value!r}"
                )

        configured_provider = str((config.get("memory") or {}).get("provider", "") or "")
        if not (config.get("memory") or {}).get("memory_enabled", True):
            configured_provider = "disabled"
        if configured_provider != spec.get("memory_provider"):
            errors.append(
                f"{name}: memory provider drift: expected={spec.get('memory_provider')} actual={configured_provider}"
            )

        sharing_class = spec.get("memory_sharing_class")
        expected_workspace = spec.get("memory_workspace")
        if sharing_class not in ALLOWED_MEMORY_SHARING_CLASSES:
            errors.append(
                f"{name}: memory sharing class must be one of {sorted(ALLOWED_MEMORY_SHARING_CLASSES)}"
            )
        elif sharing_class == "general-shared":
            if configured_provider != "honcho" or expected_workspace != general_shared_workspace:
                errors.append(
                    f"{name}: general-shared memory sharing class requires honcho workspace {general_shared_workspace!r}"
                )
        elif sharing_class == "sensitive-isolated":
            if (
                configured_provider != "honcho"
                or not isinstance(expected_workspace, str)
                or not expected_workspace.strip()
                or expected_workspace == general_shared_workspace
            ):
                errors.append(
                    f"{name}: sensitive-isolated memory sharing class requires a non-general honcho workspace"
                )
            elif expected_workspace in sensitive_workspace_owners:
                errors.append(
                    f"{name}: sensitive workspace {expected_workspace!r} is already owned by {sensitive_workspace_owners[expected_workspace]}"
                )
            else:
                sensitive_workspace_owners[expected_workspace] = name
        elif sharing_class == "profile-local" and (
            configured_provider != "builtin" or expected_workspace is not None
        ):
            errors.append(
                f"{name}: profile-local memory sharing class requires builtin provider and no workspace"
            )
        elif sharing_class == "disabled" and (
            configured_provider != "disabled" or expected_workspace is not None
        ):
            errors.append(
                f"{name}: disabled memory sharing class requires disabled memory and no workspace"
            )

        if expected_workspace is not None:
            if configured_provider != "honcho":
                errors.append(
                    f"{name}: memory_workspace requires the honcho provider"
                )
            elif not isinstance(expected_workspace, str) or not expected_workspace.strip():
                errors.append(f"{name}: memory_workspace must be a non-empty string")
            else:
                honcho_path = honcho_config_path(home, root)
                try:
                    honcho = json.loads(honcho_path.read_text())
                except (OSError, json.JSONDecodeError):
                    errors.append(f"{name}: missing or invalid honcho.json")
                else:
                    host_key = "hermes" if name == "default" else f"hermes_{name}"
                    hosts = honcho.get("hosts") if isinstance(honcho, dict) else None
                    host = hosts.get(host_key, {}) if isinstance(hosts, dict) else {}
                    actual_workspace = (
                        host.get("workspace") if isinstance(host, dict) else None
                    ) or (honcho.get("workspace") if isinstance(honcho, dict) else None)
                    if actual_workspace != expected_workspace:
                        errors.append(
                            f"{name}: Honcho workspace drift: "
                            f"expected={expected_workspace} actual={actual_workspace!r}"
                        )

        for field in (
            "role",
            "primary_domains",
            "non_goals",
            "canonical_paths",
            "summary_policy",
            "kanban_role",
            "gateway_expected",
        ):
            if field not in spec:
                errors.append(f"{name}: registry missing {field}")
        summary_policy = spec.get("summary_policy")
        if summary_policy not in ALLOWED_SUMMARY_POLICIES:
            errors.append(
                f"{name}: summary_policy must be one of "
                f"{sorted(ALLOWED_SUMMARY_POLICIES)}"
            )
        elif summary_policy == "blocked" and (
            not isinstance(spec.get("summary_policy_reason"), str)
            or not spec["summary_policy_reason"].strip()
        ):
            errors.append(
                f"{name}: blocked summary_policy requires summary_policy_reason"
            )
        summary_path = spec.get("summary_path")
        if summary_policy == "none" and summary_path is not None:
            errors.append(f"{name}: summary_policy none requires null summary_path")
        elif summary_policy in ALLOWED_SUMMARY_POLICIES - {"none"} and (
            not isinstance(summary_path, str) or summary_path.count("{week}") != 1
        ):
            errors.append(
                f"{name}: summary_policy {summary_policy} requires a string "
                "summary_path containing exactly one {week}"
            )
        expected_gateway = spec.get("gateway_expected")
        if expected_gateway not in {"running", "stopped"}:
            errors.append(
                f"{name}: gateway_expected must be running or stopped"
            )
        elif gateway_state is not None:
            actual_gateway = gateway_state(name)
            if actual_gateway != expected_gateway:
                errors.append(
                    f"{name}: gateway state drift: expected={expected_gateway} "
                    f"actual={actual_gateway}"
                )

    routing = registry.get("routing") or {}
    for topic, route in routing.items():
        references = [route.get("primary"), *(route.get("coordination") or [])]
        unknown = sorted({item for item in references if item not in expected})
        if unknown:
            errors.append(f"routing {topic}: unknown profiles {unknown}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument(
        "--registry",
        type=Path,
        default=Path.home() / ".local/share/hermes/profile-registry.json",
    )
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument(
        "--skip-gateways",
        action="store_true",
        help="validate config/registry policy without querying live systemd units",
    )
    args = parser.parse_args()
    gateway_state = None
    if not args.skip_gateways and shutil.which("systemctl"):
        gateway_state = systemd_gateway_state
    errors = validate(
        args.home.expanduser(),
        args.registry.expanduser(),
        gateway_state=gateway_state,
    )
    if errors:
        print("PROFILE_REGISTRY_INVALID")
        for error in errors:
            print(f"- {error}")
        return 1
    if args.verbose:
        registry = json.loads(args.registry.expanduser().read_text())
        print(
            f"PROFILE_REGISTRY_OK profiles={len(registry['profiles'])} "
            f"routes={len(registry.get('routing', {}))}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
