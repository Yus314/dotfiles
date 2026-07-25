#!/usr/bin/env python3
"""Converge Hermes' computer-use-linux MCP entry to a read-only pilot."""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

import yaml

READ_ONLY_TOOLS = ["doctor", "list_apps", "get_app_state"]


def mapping(parent: dict, key: str, *, path: str) -> dict:
    if key not in parent:
        parent[key] = {}
    value = parent[key]
    if not isinstance(value, dict):
        raise ValueError(f"{path}.{key} must be a mapping")
    return value


def configured(config: dict, command: str) -> dict:
    servers = mapping(config, "mcp_servers", path="config")
    existing = servers.get("computer-use-linux")
    if existing is not None and not isinstance(existing, dict):
        raise ValueError("config.mcp_servers.computer-use-linux must be a mapping")
    servers["computer-use-linux"] = {
        "command": command,
        "args": [],
        "enabled": True,
        "timeout": 30,
        "connect_timeout": 10,
        "sampling": {"enabled": False},
        "tools": {"include": READ_ONLY_TOOLS},
    }
    return config


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


def apply(path: Path, command: str) -> None:
    if path.exists():
        try:
            loaded = yaml.safe_load(path.read_text())
        except yaml.YAMLError as error:
            raise ValueError(f"invalid Hermes config {path}: {error}") from error
        if not isinstance(loaded, dict):
            raise ValueError(f"Hermes config is not a mapping: {path}")
        config = loaded
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        config = {}
    write_yaml_atomic(path, configured(config, command))


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {argv[0]} CONFIG_PATH COMMAND", file=sys.stderr)
        return 2
    try:
        apply(Path(argv[1]).expanduser(), argv[2])
    except ValueError as error:
        print(f"refusing to update Hermes config: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
