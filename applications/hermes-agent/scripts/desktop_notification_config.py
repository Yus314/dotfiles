#!/usr/bin/env python3
"""Declaratively enable CLI completion bells for Hermes."""

from __future__ import annotations

import fcntl
import os
import sys
from pathlib import Path

import yaml


def load_config(path: Path) -> dict:
    if not path.exists():
        return {}
    loaded = yaml.safe_load(path.read_text(encoding="utf-8"))
    return loaded if isinstance(loaded, dict) else {}


def write_config(path: Path, config: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(
        yaml.safe_dump(config, sort_keys=False, allow_unicode=True),
        encoding="utf-8",
    )
    temporary.replace(path)


def main() -> None:
    config_path = Path(sys.argv[1]).expanduser()
    lock_path = config_path.with_suffix(config_path.suffix + ".lock")
    lock_path.parent.mkdir(parents=True, exist_ok=True)

    with lock_path.open("a+") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        config = load_config(config_path)

        display = config.get("display")
        if not isinstance(display, dict):
            display = {}
            config["display"] = display
        display["bell_on_complete"] = True

        write_config(config_path, config)


if __name__ == "__main__":
    main()
