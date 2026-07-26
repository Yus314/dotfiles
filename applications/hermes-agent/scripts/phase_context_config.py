#!/usr/bin/env python3
"""Declaratively enable phase checkpoint context switching for default Hermes."""

from __future__ import annotations

import fcntl
import os
import sys
from pathlib import Path

import yaml


def load_config(path: Path) -> dict:
    if not path.exists():
        return {}
    loaded = yaml.safe_load(path.read_text())
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

        context = config.get("context")
        if not isinstance(context, dict):
            context = {}
            config["context"] = context
        context["engine"] = "phase_checkpoint"

        plugins = config.get("plugins")
        if not isinstance(plugins, dict):
            plugins = {}
            config["plugins"] = plugins
        enabled_plugins = plugins.get("enabled")
        if not isinstance(enabled_plugins, list):
            enabled_plugins = []
        plugins["enabled"] = sorted(
            {str(name) for name in enabled_plugins if str(name).strip()}
            | {"phase_checkpoint"}
        )

        compression = config.get("compression")
        if not isinstance(compression, dict):
            compression = {}
            config["compression"] = compression
        compression["enabled"] = True
        compression["in_place"] = True
        # In Codex app-server mode, "native" waits for Codex's own pressure
        # threshold and ignores an engine-requested phase boundary. "hermes"
        # lets the selected engine trigger Codex's native thread compaction.
        compression["codex_app_server_auto"] = "hermes"

        write_config(config_path, config)


if __name__ == "__main__":
    main()
