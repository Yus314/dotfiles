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


def profile_root(home: Path, name: str) -> Path:
    return home / ".hermes" if name == "default" else home / ".hermes/profiles" / name


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
    if registry.get("schema_version") != 1:
        errors.append("registry schema_version must be 1")
    profiles = registry.get("profiles")
    if not isinstance(profiles, dict):
        return [*errors, "registry profiles must be an object"]

    actual = discovered_profiles(home)
    expected = set(profiles)
    control_plane = registry.get("control_plane")
    if control_plane not in expected:
        errors.append(f"control_plane references unknown profile: {control_plane}")
    if actual != expected:
        errors.append(
            f"profile roster drift: missing={sorted(expected-actual)} unexpected={sorted(actual-expected)}"
        )

    for name, spec in sorted(profiles.items()):
        if not isinstance(spec, dict):
            errors.append(f"{name}: registry entry is not an object")
            continue
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
        external_dirs = ((config.get("skills") or {}).get("external_dirs") or [])
        shared_root = home / ".local/share/hermes/shared-skills"
        managed_groups = []
        for item in external_dirs:
            if not isinstance(item, str):
                continue
            expanded = Path(os.path.expandvars(os.path.expanduser(item)))
            if not expanded.is_absolute():
                expanded = root / expanded
            for group in (
                "common",
                "study",
                "engineering",
                "orchestration",
                "profile-ops",
            ):
                if expanded == shared_root / group:
                    managed_groups.append(group)
                    break
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

        for field in (
            "role",
            "primary_domains",
            "non_goals",
            "canonical_paths",
            "kanban_role",
            "gateway_expected",
        ):
            if field not in spec:
                errors.append(f"{name}: registry missing {field}")
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
