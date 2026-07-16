#!/usr/bin/env python3
"""Fail-closed validation for a Hermes Discord profile before gateway startup."""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

PROTECTED_ENV_KEYS = {
    "DISCORD_BOT_TOKEN",
    "DISCORD_ALLOWED_USERS",
    "DISCORD_ALLOWED_CHANNELS",
    "DISCORD_ALLOW_ALL_USERS",
    "DISCORD_ALLOWED_ROLES",
    "DISCORD_DM_ROLE_AUTH_GUILD",
    "DISCORD_ALLOW_BOTS",
    "GATEWAY_ALLOWED_USERS",
    "GATEWAY_ALLOW_ALL_USERS",
}


def normalized_channels(raw: object) -> set[str]:
    if isinstance(raw, (str, int)):
        return {part.strip() for part in str(raw).split(",") if part.strip()}
    if isinstance(raw, list):
        return {str(value).strip() for value in raw if str(value).strip()}
    return set()


def protected_dotenv_keys(path: Path) -> set[str]:
    protected: set[str] = set()
    for line in path.read_text(errors="replace").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        for key in PROTECTED_ENV_KEYS:
            if re.search(rf"{re.escape(key)}\s*=", stripped):
                protected.add(key)
        for match in re.finditer(r"(DISCORD_[A-Za-z0-9_]*TOKEN[A-Za-z0-9_]*)\s*=", stripped):
            protected.add(match.group(1))
        if re.search(r"DISCORD_FOOD\s*=", stripped):
            protected.add("DISCORD_FOOD")
    return protected


def validate(config_path: Path, expected: str) -> None:
    if not config_path.is_file():
        raise ValueError(f"missing profile config: {config_path}")
    try:
        config = yaml.safe_load(config_path.read_text())
    except yaml.YAMLError as error:
        raise ValueError(f"invalid profile config {config_path}: {error}") from error
    if not isinstance(config, dict):
        raise ValueError(f"profile config is not a mapping: {config_path}")

    env_path = config_path.parent / ".env"
    if not env_path.is_file():
        raise ValueError(
            f"missing profile dotenv: {env_path}; it is required to prevent project dotenv fallback overrides"
        )
    protected = sorted(protected_dotenv_keys(env_path))
    if protected:
        raise ValueError(
            f"profile dotenv defines gateway-protected variables {protected}: {env_path}"
        )

    secrets = config.get("secrets")
    if isinstance(secrets, dict):
        bitwarden = secrets.get("bitwarden")
        if (
            isinstance(bitwarden, dict)
            and bitwarden.get("enabled")
            and bitwarden.get("override_existing")
        ):
            raise ValueError(
                "Bitwarden override_existing must be false for a hardened gateway profile"
            )

    discord = config.get("discord")
    if not isinstance(discord, dict):
        raise ValueError(f"discord config is not a mapping: {config_path}")
    values = normalized_channels(discord.get("allowed_channels"))
    if values != {expected}:
        raise ValueError(
            f"discord.allowed_channels must be exactly {expected}; got {sorted(values)}"
        )


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {argv[0]} CONFIG_PATH EXPECTED_CHANNEL", file=sys.stderr)
        return 2
    try:
        validate(Path(argv[1]).expanduser(), argv[2])
    except ValueError as error:
        print(f"refusing to start: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
