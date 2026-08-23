#!/usr/bin/env python3
"""Value-hidden fail-closed preflight for W40 production-SHADOW registration."""
from __future__ import annotations

import argparse
import hashlib
import os
import stat
import sys
from pathlib import Path

import yaml

ENV_NAMES = (
    "HERMES_NATURAL_OK_OWNER_ACTOR_SHA256",
    "HERMES_NATURAL_OK_SCOPE_CHAT_ID",
    "HERMES_NATURAL_OK_SCOPE_THREAD_ID",
    "HERMES_NATURAL_OK_SCOPE_GUILD_ID",
    "HERMES_NATURAL_OK_SCOPE_PARENT_CHAT_ID",
)
PLUGIN_NAME = "natural-ok-unified-shadow"
NULL_SENTINEL = "null"
PLACEHOLDER_PREFIX = "__SET_"
EXPECTED_VERSION = "0.19.0"
EXPECTED_BASELINE = {
    "gateway/run.py": "c6e0f443772e4a8a7eac0d9ccf9a4f659de5fc5493c572a69a46e4c61a8aa966",
    "agent/turn_context.py": "fa273c7496c4e06a8c1834f835acdf8b0b12e7302d9ed9048118f4a3f442178d",
    "plugins/platforms/discord/adapter.py": "84b0f4912d6661ab57b102bb6d0509206b6383ba1384feae80b5894d320466d7",
}
EXPECTED_PATCHED = {
    "gateway/run.py": "b816475affba3ae946ffb8dd365d7da8b29a1b877148d331abdf5b16a4e4e425",
    "agent/turn_context.py": "5752abc7ec12966a1ef4a6f77e3cbba8f9dcfec78f161f6268d4e06c244cb02e",
    "plugins/platforms/discord/adapter.py": "c2ce0a2dcf645e19bf7c4bf3de341c2cc18da93fe290783f940b589f6c667713",
    "plugins/natural-ok-unified-shadow/__init__.py": "9e3299c64984446a0c938369fdaa069d3258c2e3cf07737b2a23ad402f0df221",
    "plugins/natural-ok-unified-shadow/core/state.py": "455336733e0494f4be524cede77fa8ab997f05e9ea4e062afb4c90b31d2fa91d",
}
EXPECTED_W40_PATCH_SHA256 = "7f7f1b6ebeda471be511030c8e90c2cd5be54deef7bba2eec103e9e8e9ddf027"
EXPECTED_W50_PATCH_SHA256 = "583b0a57c422b6822922c8121da8d772566c18fd3404e2bd1989a8e1a850f35d"


class Refusal(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_id(value: str) -> bool:
    return (
        type(value) is str and 1 <= len(value) <= 20 and value[0] in "123456789"
        and value.isascii() and value.isdigit() and int(value) <= (1 << 64) - 1
    )


def check_environment() -> None:
    present = [name in os.environ for name in ENV_NAMES]
    if any(present) and not all(present):
        raise Refusal("scope environment must be all-or-nothing")
    if not all(present):
        raise Refusal("scope environment is absent")
    values = [os.environ[name] for name in ENV_NAMES]
    if any(not value or value.startswith(PLACEHOLDER_PREFIX) for value in values):
        raise Refusal("scope environment contains missing/placeholder encoding")
    owner, chat, *optional = values
    if len(owner) != 64 or any(character not in "0123456789abcdef" for character in owner):
        raise Refusal("owner actor digest is malformed")
    if not canonical_id(chat):
        raise Refusal("required chat scope is malformed")
    for value in optional:
        if value != NULL_SENTINEL and not canonical_id(value):
            raise Refusal("optional scope must be canonical ID or literal null")


def check_state_root(path_text: str) -> None:
    path = Path(path_text)
    if not path.is_absolute() or str(path) != path_text or ".." in path.parts:
        raise Refusal("state root is not lexical absolute")
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for component in path.parts[1:]:
            next_fd = os.open(
                component,
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                dir_fd=fd,
            )
            os.close(fd)
            fd = next_fd
        metadata = os.fstat(fd)
        if not stat.S_ISDIR(metadata.st_mode):
            raise Refusal("state root is not a directory")
        if stat.S_IMODE(metadata.st_mode) != 0o700:
            raise Refusal("state root mode is not 0700")
        if metadata.st_uid != os.getuid():
            raise Refusal("state root owner differs from service user")
    finally:
        os.close(fd)


def check_config(path: Path) -> None:
    loaded = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(loaded, dict):
        raise Refusal("Hermes config is malformed")
    plugins = loaded.get("plugins")
    enabled = plugins.get("enabled") if isinstance(plugins, dict) else None
    if not isinstance(enabled, list) or PLUGIN_NAME not in enabled:
        raise Refusal("shadow plugin is not explicitly enabled")


def check_hashes(root: Path, expected: dict[str, str], label: str) -> None:
    for relative, wanted in expected.items():
        path = root / relative
        if not path.is_file() or sha256(path) != wanted:
            raise Refusal(f"{label} source hash mismatch: {relative}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--state-root", required=True)
    parser.add_argument("--version-file", required=True)
    parser.add_argument("--baseline-root", required=True)
    parser.add_argument("--patched-root", required=True)
    parser.add_argument("--patch", required=True)
    parser.add_argument("--w50-patch", required=True)
    args = parser.parse_args()
    try:
        version = Path(args.version_file).read_text(encoding="utf-8").strip()
        if version != EXPECTED_VERSION:
            raise Refusal("installed Hermes version mismatch")
        check_environment()
        check_state_root(args.state_root)
        check_config(Path(args.config))
        check_hashes(Path(args.baseline_root), EXPECTED_BASELINE, "baseline")
        check_hashes(Path(args.patched_root), EXPECTED_PATCHED, "patched")
        if sha256(Path(args.patch)) != EXPECTED_W40_PATCH_SHA256:
            raise Refusal("W40 patch hash mismatch")
        if sha256(Path(args.w50_patch)) != EXPECTED_W50_PATCH_SHA256:
            raise Refusal("W50 patch hash mismatch")
    except (OSError, ValueError, yaml.YAMLError, Refusal) as exc:
        print(f"W50 production-SHADOW preflight: REFUSE ({exc})", file=sys.stderr)
        return 1
    print("W50 production-SHADOW preflight: PASS (values hidden; synthetic_noop/HOLD)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
