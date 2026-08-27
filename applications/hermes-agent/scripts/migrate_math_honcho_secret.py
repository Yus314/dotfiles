#!/usr/bin/env python3
"""Copy the existing Lawliet Honcho credential into the math SOPS field.

The credential stays in memory and on subprocess stdin. This command never
prints the value, a suffix, or a value-derived digest.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SECRET_FILE = ROOT / "secrets.yaml"
DEFAULT_LAWLIET_ENV = Path.home() / ".hermes" / ".env"
SOURCE_INDEX = '["env"]'
TARGET_INDEX = '["math_honcho_env"]'


def fail(message: str) -> None:
    raise SystemExit(f"migration blocked: {message}")


def extract_honcho_value(dotenv: str) -> str | None:
    matches = [
        line.partition("=")[2]
        for line in dotenv.splitlines()
        if line.startswith("HONCHO_API_KEY=")
    ]
    if not matches:
        return None
    if len(matches) != 1 or not matches[0]:
        fail("credential source must contain exactly one non-empty HONCHO_API_KEY entry")
    return matches[0]


def migrate(secret_file: Path, lawliet_env: Path, sops: str) -> None:
    decrypted = subprocess.run(
        [sops, "decrypt", "--extract", SOURCE_INDEX, str(secret_file)],
        text=True,
        capture_output=True,
    )
    if decrypted.returncode != 0:
        fail("cannot decrypt the existing SOPS env noninteractively; unlock the repository SOPS key and rerun")

    value = extract_honcho_value(decrypted.stdout)
    if value is None:
        if lawliet_env.is_symlink() or not lawliet_env.is_file():
            fail(
                "HONCHO_API_KEY is absent from the SOPS env and the regular Lawliet ~/.hermes/.env source is unavailable"
            )
        value = extract_honcho_value(lawliet_env.read_text(encoding="utf-8"))
    if value is None:
        fail("HONCHO_API_KEY is missing from both approved sources")
    target = json.dumps(f"HONCHO_API_KEY={value}\n")
    updated = subprocess.run(
        [sops, "set", "--value-stdin", str(secret_file), TARGET_INDEX],
        input=target,
        text=True,
        capture_output=True,
    )
    if updated.returncode != 0:
        fail("sops set failed; the encrypted file was not safely migrated")
    print("source=present target=present")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--secret-file", type=Path, default=DEFAULT_SECRET_FILE)
    parser.add_argument("--lawliet-env", type=Path, default=DEFAULT_LAWLIET_ENV)
    parser.add_argument("--sops", default=shutil.which("sops"))
    args = parser.parse_args()
    if not args.sops:
        fail("sops executable is missing")
    if not args.secret_file.is_file():
        fail("applications/hermes-agent/secrets.yaml is missing")
    migrate(args.secret_file.resolve(), args.lawliet_env.expanduser(), args.sops)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
