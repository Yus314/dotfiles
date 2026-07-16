#!/usr/bin/env python3
"""Enforce one Hermes Kanban dispatcher across all registered profiles."""
from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path

import yaml


def profile_root(home: Path, profile: str) -> Path:
    return home / ".hermes" if profile == "default" else home / ".hermes/profiles" / profile


def desired_profiles(registry_path: Path) -> tuple[str, list[str]]:
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    control = registry.get("control_plane")
    profiles = registry.get("profiles")
    if not isinstance(profiles, dict) or control not in profiles:
        raise ValueError("registry must name a valid control_plane profile")
    return str(control), sorted(str(name) for name in profiles)


def expected_dispatch(profile: str, control_plane: str) -> bool:
    return profile == control_plane


def check(home: Path, registry_path: Path) -> list[str]:
    control, profiles = desired_profiles(registry_path)
    errors: list[str] = []
    for profile in profiles:
        path = profile_root(home, profile) / "config.yaml"
        if not path.is_file():
            errors.append(f"{profile}: missing config: {path}")
            continue
        loaded = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        kanban = loaded.get("kanban") if isinstance(loaded, dict) else None
        expected = expected_dispatch(profile, control)
        if not isinstance(kanban, dict):
            errors.append(f"{profile}: missing kanban configuration")
            continue
        for key in ("dispatch_in_gateway", "auto_decompose"):
            if kanban.get(key) is not expected:
                errors.append(
                    f"{profile}: kanban.{key} expected={expected} actual={kanban.get(key)!r}"
                )
    return errors


def atomic_yaml_write(path: Path, data: dict) -> None:
    mode = path.stat().st_mode & 0o777
    fd, raw_tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    tmp = Path(raw_tmp)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            yaml.safe_dump(data, handle, sort_keys=False, allow_unicode=True)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def configure(home: Path, registry_path: Path) -> list[str]:
    control, profiles = desired_profiles(registry_path)
    planned: list[tuple[str, Path, dict]] = []
    for profile in profiles:
        path = profile_root(home, profile) / "config.yaml"
        if not path.is_file():
            raise FileNotFoundError(f"{profile}: missing config: {path}")
        loaded = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        if not isinstance(loaded, dict):
            raise ValueError(f"{profile}: config root is not a mapping")
        kanban = loaded.setdefault("kanban", {})
        if not isinstance(kanban, dict):
            raise ValueError(f"{profile}: kanban config is not a mapping")
        expected = expected_dispatch(profile, control)
        before = (kanban.get("dispatch_in_gateway"), kanban.get("auto_decompose"))
        kanban["dispatch_in_gateway"] = expected
        kanban["auto_decompose"] = expected
        if before != (expected, expected):
            planned.append((profile, path, loaded))

    # Do not mutate any profile until every target has parsed and validated.
    # Individual writes remain atomic; this preflight prevents predictable
    # missing/malformed later profiles from leaving a partial policy rollout.
    for _profile, path, loaded in planned:
        atomic_yaml_write(path, loaded)
    return [profile for profile, _path, _loaded in planned]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("check", "configure"))
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument(
        "--registry",
        type=Path,
        default=Path.home() / ".local/share/hermes/profile-registry.json",
    )
    args = parser.parse_args()
    if args.action == "configure":
        changed = configure(args.home, args.registry)
        if changed:
            print(json.dumps({"changed_profiles": changed}, sort_keys=True))
    errors = check(args.home, args.registry)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
