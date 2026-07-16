#!/usr/bin/env python3
"""Apply declarative, type-safe Hermes research/model configuration."""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

import yaml

MODEL_SLUGS = ("gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5")


def mapping(parent: dict, key: str, *, path: str) -> dict:
    if key not in parent:
        parent[key] = {}
    value = parent[key]
    if not isinstance(value, dict):
        raise ValueError(f"{path}.{key} must be a mapping")
    return value


def configured(config: dict, home: Path) -> dict:
    web = mapping(config, "web", path="config")
    web.update(
        backend="firecrawl",
        search_backend="exa",
        extract_backend="firecrawl",
    )

    model = mapping(config, "model", path="config")
    model.update(
        default="gpt-5.6-sol",
        provider="openai-codex",
        base_url="https://chatgpt.com/backend-api/codex",
    )

    auxiliary = mapping(config, "auxiliary", path="config")
    for key in ("compression", "title_generation"):
        section = mapping(auxiliary, key, path="config.auxiliary")
        section.update(provider="openai-codex", model="gpt-5.6-sol")

    providers = mapping(config, "providers", path="config")
    openai_codex = mapping(providers, "openai-codex", path="config.providers")
    models = mapping(openai_codex, "models", path="config.providers.openai-codex")
    for slug in MODEL_SLUGS:
        model_config = mapping(models, slug, path="config.providers.openai-codex.models")
        model_config["stale_timeout_seconds"] = 300

    servers = mapping(config, "mcp_servers", path="config")
    existing_server = servers.get("research_providers")
    if existing_server is not None and not isinstance(existing_server, dict):
        raise ValueError("config.mcp_servers.research_providers must be a mapping")
    servers["research_providers"] = {
        "command": "uv",
        "args": [
            "run",
            "--with",
            "mcp",
            str(home / ".hermes/mcp/research_providers_server.py"),
        ],
        "enabled": True,
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


def apply(path: Path, home: Path) -> None:
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
    write_yaml_atomic(path, configured(config, home))


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} CONFIG_PATH", file=sys.stderr)
        return 2
    try:
        apply(Path(argv[1]).expanduser(), Path.home())
    except ValueError as error:
        print(f"refusing to update Hermes config: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
