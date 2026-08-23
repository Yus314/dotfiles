"""Configured production-SHADOW registration wrapper for the frozen W40 plane.

This wrapper can only issue synthetic_noop prompts and record non-authoritative,
hash-only evidence.  It has no network client, sender, executor, or action path.
Invalid or incomplete environment leaves the tool unavailable and hooks inert.
"""
from __future__ import annotations

import json
import os
import stat
import subprocess
import time
from pathlib import Path
from typing import Any, Optional

from .core.state import BOUNDARIES, OPERATION, PlaneConfig, RESULT_SCHEMA, TimeSample, UnifiedShadowPlane

TOOL_NAME = "natural_ok_shadow_issue"
TOOLSET = "natural-ok-unified-shadow"
ENV_NAMES = (
    "HERMES_NATURAL_OK_OWNER_ACTOR_SHA256",
    "HERMES_NATURAL_OK_SCOPE_CHAT_ID",
    "HERMES_NATURAL_OK_SCOPE_THREAD_ID",
    "HERMES_NATURAL_OK_SCOPE_GUILD_ID",
    "HERMES_NATURAL_OK_SCOPE_PARENT_CHAT_ID",
)
STATE_ROOT_ENV = "HERMES_NATURAL_OK_STATE_ROOT"
TIMEDATECTL_ENV = "HERMES_NATURAL_OK_TIMEDATECTL"
NULL_SENTINEL = "null"
PLACEHOLDER_PREFIX = "__SET_"
TOOL_SCHEMA = {
    "name": TOOL_NAME,
    "description": "Create an offline synthetic/no-op shadow prompt; no approval or action is possible.",
    "parameters": {
        "type": "object",
        "additionalProperties": False,
        "required": ["description", "target_sha256", "expiry_seconds"],
        "properties": {
            "description": {"type": "string", "minLength": 1, "maxLength": 256},
            "target_sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
            "expiry_seconds": {"type": "integer", "minimum": 1, "maximum": 900},
        },
    },
}


def _canonical_id(value: str) -> bool:
    return (
        type(value) is str
        and 1 <= len(value) <= 20
        and value[0] in "123456789"
        and value.isascii()
        and value.isdigit()
        and int(value) <= (1 << 64) - 1
    )


def _optional_id(value: str) -> Optional[str]:
    if value == NULL_SENTINEL:
        return None
    if not _canonical_id(value):
        raise ValueError("invalid optional scope encoding")
    return value


def _verify_exact_state_root(path_text: str) -> None:
    root = Path(path_text)
    if not root.is_absolute() or str(root) != path_text or ".." in root.parts:
        raise ValueError("state root must be lexical absolute")
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for component in root.parts[1:]:
            next_fd = os.open(
                component,
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                dir_fd=fd,
            )
            os.close(fd)
            fd = next_fd
        metadata = os.fstat(fd)
        if (
            not stat.S_ISDIR(metadata.st_mode)
            or stat.S_IMODE(metadata.st_mode) != 0o700
            or metadata.st_uid != os.getuid()
        ):
            raise ValueError("state root type, mode, or owner mismatch")
    finally:
        os.close(fd)


def _systemd_time_sample() -> TimeSample:
    executable = os.environ.get(TIMEDATECTL_ENV, "")

    def probe() -> bool:
        try:
            completed = subprocess.run(
                [executable, "show", "--property=NTPSynchronized", "--value"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=2,
                check=False,
                env={"LC_ALL": "C", "LANG": "C"},
            )
        except (OSError, subprocess.SubprocessError):
            return False
        return completed.returncode == 0 and completed.stdout == b"yes\n"

    before = probe()
    try:
        unix_seconds = int(time.time())
    except Exception:
        return TimeSample(0, False)
    after = probe()
    return TimeSample(unix_seconds, before and after and unix_seconds >= 0)


def _load_plane() -> Optional[UnifiedShadowPlane]:
    try:
        values = {name: os.environ[name] for name in ENV_NAMES}
        state_root_raw = os.environ[STATE_ROOT_ENV]
        timedatectl = os.environ[TIMEDATECTL_ENV]
        if any(not value or value.startswith(PLACEHOLDER_PREFIX) for value in values.values()):
            raise ValueError("missing or placeholder environment")
        owner = values[ENV_NAMES[0]]
        if len(owner) != 64 or any(c not in "0123456789abcdef" for c in owner):
            raise ValueError("invalid owner digest")
        chat = values[ENV_NAMES[1]]
        if not _canonical_id(chat):
            raise ValueError("invalid required scope")
        _verify_exact_state_root(state_root_raw)
        timedate_path = Path(timedatectl)
        if not timedate_path.is_absolute() or not timedate_path.is_file():
            raise ValueError("invalid local time probe")
        return UnifiedShadowPlane(
            PlaneConfig(
                state_root=state_root_raw,
                owner_actor_sha256=owner,
                time_provider=_systemd_time_sample,
                approval_chat_id=chat,
                approval_thread_id=_optional_id(values[ENV_NAMES[2]]),
                approval_guild_id=_optional_id(values[ENV_NAMES[3]]),
                approval_parent_chat_id=_optional_id(values[ENV_NAMES[4]]),
            )
        )
    except Exception:
        return None


def _failure(reason: str) -> dict[str, Any]:
    result = {
        "schema": RESULT_SCHEMA,
        "action": "allow",
        "reason": reason,
        "success": False,
        "operation": dict(OPERATION),
    }
    result.update(BOUNDARIES)
    return result


_PLANE = _load_plane()


def _configured() -> bool:
    return _PLANE is not None


def _tool(args: Any, **kwargs: Any) -> str:
    if _PLANE is None:
        result = _failure("unconfigured")
        result["error"] = {"code": "UNCONFIGURED", "message": "Shadow plane is not configured."}
        return json.dumps(result, sort_keys=True, separators=(",", ":"))
    try:
        if type(args) is not dict or set(args) != {"description", "target_sha256", "expiry_seconds"}:
            raise ValueError("invalid tool argument schema")
        result = _PLANE.issue(
            args["description"], args["target_sha256"], args["expiry_seconds"],
            session_id=kwargs.get("session_id"),
        )
        return json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    except Exception as exc:
        result = _failure("fail-closed")
        result["action"] = "refuse"
        result["error"] = {"code": type(exc).__name__.upper(), "message": "Shadow issuance failed closed."}
        return json.dumps(result, sort_keys=True, separators=(",", ":"))


def _gateway(**kwargs: Any) -> dict[str, Any]:
    if _PLANE is None:
        return _failure("candidate-unconfigured-no-authority")
    try:
        return _PLANE.pre_gateway_dispatch(**kwargs)
    except Exception:
        result = _failure("fail-closed")
        result["action"] = "skip"
        return result


def _pre_llm(**kwargs: Any) -> None:
    if _PLANE is not None:
        try:
            _PLANE.pre_llm_call(**kwargs)
        except Exception:
            pass
    return None


def register(ctx: Any) -> None:
    ctx.register_hook("pre_gateway_dispatch", _gateway)
    ctx.register_hook("pre_llm_call", _pre_llm)
    ctx.register_tool(
        name=TOOL_NAME,
        toolset=TOOLSET,
        schema=TOOL_SCHEMA,
        handler=_tool,
        check_fn=_configured,
        description="Configured non-actionable W40 production-SHADOW plane.",
        emoji="🕶️",
    )


__all__ = ["TOOL_SCHEMA", "register"]
