#!/usr/bin/env python3
"""Declaratively set one exact Discord channel per Hermes profile."""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

import yaml


def config_path(home: Path, profile: str) -> Path:
    if profile == "default":
        return home / ".hermes/config.yaml"
    return home / ".hermes/profiles" / profile / "config.yaml"


def load_updates(home: Path, channels: dict[str, str]) -> list[tuple[Path, dict]]:
    updates: list[tuple[Path, dict]] = []
    for profile, channel in channels.items():
        path = config_path(home, profile)
        if not path.is_file():
            raise ValueError(f"missing Hermes profile config: {path}")
        try:
            loaded = yaml.safe_load(path.read_text())
        except yaml.YAMLError as error:
            raise ValueError(f"invalid Hermes profile config {path}: {error}") from error
        if not isinstance(loaded, dict):
            raise ValueError(f"Hermes profile config is not a mapping: {path}")
        config = loaded
        discord = config.get("discord")
        if discord is None:
            discord = {}
            config["discord"] = discord
        elif not isinstance(discord, dict):
            raise ValueError(f"discord config is not a mapping: {path}")
        discord["allowed_channels"] = str(channel)
        updates.append((path, config))
    return updates


def write_yaml_atomic(path: Path, value: dict) -> None:
    rendered = yaml.safe_dump(value, sort_keys=False, allow_unicode=True)
    fd, temporary_name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", text=True)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(rendered)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary_path, 0o600)
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def apply(home: Path, channels: dict[str, str]) -> None:
    updates = load_updates(home, channels)
    for path, config in updates:
        write_yaml_atomic(path, config)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} CHANNEL_MAP_JSON", file=sys.stderr)
        return 2
    try:
        raw = json.loads(argv[1])
        if not isinstance(raw, dict) or not raw:
            raise ValueError("channel map must be a non-empty object")
        channels = {str(profile): str(channel) for profile, channel in raw.items()}
        if any(not channel.strip() for channel in channels.values()):
            raise ValueError("channel IDs must be non-empty")
        apply(Path.home(), channels)
    except (json.JSONDecodeError, ValueError) as error:
        print(f"refusing to update gateway channels: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
