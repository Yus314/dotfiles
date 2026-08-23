"""Unified W40 non-actionable approval state plane (standard library only)."""
from __future__ import annotations

import errno
import fcntl
import hashlib
import hmac
import json
import os
import re
import stat
import threading
from dataclasses import dataclass
from typing import Any, Callable, Mapping, Optional

REQUEST_SCHEMA = "natural-ok-unified-shadow-request-v1"
EVIDENCE_SCHEMA = "natural-ok-unified-shadow-evidence-v1"
HIGH_WATER_SCHEMA = "natural-ok-unified-high-water-v1"
RESULT_SCHEMA = "natural-ok-unified-shadow-result-v1"
OPERATION = {"kind": "synthetic_noop", "actionable": False}
BOUNDARIES = {
    "identity_proof": False,
    "owner_approval_proven": False,
    "authorization_granted": False,
    "action_executed": False,
    "semantic_proof": False,
    "actionable": False,
    "ordinary_use": "HOLD",
    "shared_default_rollout": "HOLD",
}
MAX_DESCRIPTION_BYTES = 256
MAX_PROMPT_BYTES = 1900
MAX_RECORD_BYTES = 16_384
MAX_PENDING = 8
MAX_EVIDENCE = 256
MAX_EVIDENCE_AGE = 30 * 86400
MAX_TTL = 900
MAX_SCOPES = 64
MAX_STATE_ENTRIES = MAX_PENDING + MAX_EVIDENCE + 3
SCOPE_TTL_MONOTONIC = 15.0
LOCK_NAME = ".natural-ok.lock"
REQUEST_RE = re.compile(r"request-([0-9a-f]{32})\.json\Z")
EVIDENCE_RE = re.compile(r"evidence-([0-9a-f]{64})\.json\Z")
MARKER_RE = re.compile(
    r"\[HERMES-SHADOW-APPROVAL-V1 request=([0-9a-f]{32}) nonce=([0-9a-f]{32})\]\Z"
)
HEX64_RE = re.compile(r"[0-9a-f]{64}\Z")
_PROCESS_LOCK = threading.Lock()


class Refused(RuntimeError):
    """Stable fail-closed error; messages contain no untrusted payload."""


@dataclass(frozen=True)
class TimeSample:
    unix_seconds: int
    synchronized: bool = True


@dataclass(frozen=True)
class PlaneConfig:
    state_root: str
    owner_actor_sha256: str
    time_provider: Callable[[], TimeSample]
    approval_chat_id: str
    approval_thread_id: Optional[str]
    approval_guild_id: Optional[str]
    approval_parent_chat_id: Optional[str]
    random_provider: Callable[[int], bytes] = os.urandom
    monotonic_provider: Callable[[], float] = __import__("time").monotonic
    scope_ttl_monotonic: float = SCOPE_TTL_MONOTONIC
    max_scopes: int = MAX_SCOPES


@dataclass(frozen=True)
class _TurnScope:
    deadline: float
    platform: str
    user_id: str
    chat_id: str
    thread_id: Optional[str]
    guild_id: Optional[str]
    parent_chat_id: Optional[str]


@dataclass(frozen=True)
class _OpenedRoot:
    fd: int
    dev: int
    ino: int


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def actor_digest(platform: str, user_id: str) -> str:
    return hashlib.sha256(
        b"natural-ok-actor-v1\x00" + platform.encode("ascii") + b"\x00" + user_id.encode("ascii")
    ).hexdigest()


def scope_field_digest(name: str, value: Optional[str], *, required: bool = False) -> str:
    prefix = b"natural-ok-scope-v1\x00" + name.encode("ascii")
    if value is None:
        if required:
            raise Refused("missing-required-scope")
        payload = prefix + b"\x00N"
    else:
        if value == "":
            raise Refused("empty-scope-value")
        payload = prefix + b"\x00V\x00" + value.encode("utf-8", errors="strict")
    return hashlib.sha256(payload).hexdigest()


def boundary_result(action: str, reason: str, **extra: Any) -> dict[str, Any]:
    result = {"schema": RESULT_SCHEMA, "action": action, "reason": reason, **extra}
    result.update(BOUNDARIES)
    result["operation"] = dict(OPERATION)
    return result


def _canonical_discord_id(value: Any) -> Optional[str]:
    if type(value) is not str or not value or not value.isascii() or not value.isdecimal():
        return None
    if value[0] == "0" or len(value) > 20:
        return None
    try:
        number = int(value)
    except ValueError:
        return None
    return value if 1 <= number <= (1 << 64) - 1 and str(number) == value else None


def _platform(value: Any) -> Optional[str]:
    try:
        candidate = getattr(value, "value", value)
    except Exception:
        return None
    return candidate if type(candidate) is str else None


def _optional_w45(value: Any) -> Optional[str]:
    if type(value) is not str:
        raise Refused("invalid-current-source")
    if value == "":
        return None
    if _canonical_discord_id(value) is None:
        raise Refused("invalid-current-source")
    return value


def _optional_event_id(value: Any) -> Optional[str]:
    """Parse MessageEvent optional IDs; only None represents null."""
    if value is None:
        return None
    parsed = _canonical_discord_id(value)
    if parsed is None:
        raise Refused("invalid-event-source")
    return parsed


def _scope_digests(scope: _TurnScope) -> dict[str, str]:
    return {
        "platform_sha256": scope_field_digest("platform", scope.platform, required=True),
        "chat_id_sha256": scope_field_digest("chat_id", scope.chat_id, required=True),
        "thread_id_sha256": scope_field_digest("thread_id", scope.thread_id),
        "guild_id_sha256": scope_field_digest("guild_id", scope.guild_id),
        "parent_chat_id_sha256": scope_field_digest("parent_chat_id", scope.parent_chat_id),
    }


def _strict_description(value: Any) -> str:
    if type(value) is not str or not value.strip():
        raise Refused("invalid-description")
    try:
        raw = value.encode("utf-8", errors="strict")
    except UnicodeError as exc:
        raise Refused("invalid-description") from exc
    if len(raw) > MAX_DESCRIPTION_BYTES:
        raise Refused("invalid-description")
    return value


def _strict_hex64(value: Any, reason: str) -> str:
    if type(value) is not str or HEX64_RE.fullmatch(value) is None:
        raise Refused(reason)
    return value


def _strict_expiry(value: Any) -> int:
    if type(value) is not int or not 1 <= value <= MAX_TTL:
        raise Refused("invalid-expiry")
    return value


def _sample(provider: Callable[[], TimeSample]) -> int:
    try:
        sample = provider()
    except Exception as exc:
        raise Refused("trusted-time-unavailable") from exc
    if (not isinstance(sample, TimeSample) or sample.synchronized is not True
            or type(sample.unix_seconds) is not int or sample.unix_seconds < 0):
        raise Refused("trusted-time-unavailable")
    return sample.unix_seconds


def _random_hex(provider: Callable[[int], bytes]) -> str:
    try:
        raw = provider(16)
    except Exception as exc:
        raise Refused("random-unavailable") from exc
    if type(raw) is not bytes or len(raw) != 16:
        raise Refused("random-unavailable")
    return raw.hex()


def _strict_json(raw: bytes, cap: int, reason: str) -> Any:
    if type(raw) is not bytes or not raw or len(raw) > cap or raw.startswith(b"\xef\xbb\xbf"):
        raise Refused(reason)
    def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        out: dict[str, Any] = {}
        for key, value in pairs:
            if key in out:
                raise Refused(reason)
            out[key] = value
        return out
    try:
        value = json.loads(raw.decode("utf-8", errors="strict"), object_pairs_hook=unique,
                           parse_constant=lambda _x: (_ for _ in ()).throw(Refused(reason)))
    except Refused:
        raise
    except Exception as exc:
        raise Refused(reason) from exc
    if canonical_json(value) != raw:
        raise Refused(reason)
    return value


def _validate_file(st: os.stat_result, label: str) -> None:
    if (not stat.S_ISREG(st.st_mode) or st.st_uid != os.geteuid()
            or stat.S_IMODE(st.st_mode) != 0o600 or st.st_nlink != 1):
        raise Refused("unsafe-" + label)


def _verify_named(root_fd: int, name: str, fd: int, label: str) -> os.stat_result:
    held = os.fstat(fd)
    _validate_file(held, label)
    try:
        named = os.stat(name, dir_fd=root_fd, follow_symlinks=False)
    except OSError as exc:
        raise Refused(label + "-replaced") from exc
    _validate_file(named, label)
    if (held.st_dev, held.st_ino) != (named.st_dev, named.st_ino):
        raise Refused(label + "-replaced")
    return held


def _write_all(fd: int, data: bytes) -> None:
    view = memoryview(data)
    done = 0
    while done < len(view):
        try:
            count = os.write(fd, view[done:])
        except InterruptedError:
            continue
        if count <= 0:
            raise OSError(errno.EIO, "write made no progress")
        done += count


def _unlink_if_inode(root_fd: int, name: str, original: os.stat_result, *, strict: bool) -> bool:
    try:
        named = os.stat(name, dir_fd=root_fd, follow_symlinks=False)
    except FileNotFoundError:
        return True
    except OSError as exc:
        if strict:
            raise Refused("cleanup-ambiguous") from exc
        return False
    if (not stat.S_ISREG(named.st_mode) or named.st_nlink != 1
            or (named.st_dev, named.st_ino) != (original.st_dev, original.st_ino)):
        if strict:
            raise Refused("cleanup-replacement-inode")
        return False
    os.unlink(name, dir_fd=root_fd)
    os.fsync(root_fd)
    return True


def _write_exclusive(root_fd: int, name: str, data: bytes, label: str) -> os.stat_result:
    fd: Optional[int] = None
    created: Optional[os.stat_result] = None
    complete = False
    try:
        fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                     0o600, dir_fd=root_fd)
        created = os.fstat(fd)
        os.fchmod(fd, 0o600)
        created = os.fstat(fd)
        _validate_file(created, label)
        _write_all(fd, data)
        os.fsync(fd)
        _verify_named(root_fd, name, fd, label)
        os.fsync(root_fd)
        complete = True
    finally:
        if fd is not None:
            if created is None:
                # Recover identity only from the still-held descriptor.  If
                # recovery fails, closing without pathname deletion is safe.
                try:
                    created = os.fstat(fd)
                except Exception:
                    created = None
            try:
                os.close(fd)
            except OSError:
                pass
        if not complete and created is not None:
            try:
                _unlink_if_inode(root_fd, name, created, strict=False)
            except OSError:
                pass
    assert created is not None
    return created


def _replace_high_water(root_fd: int, now: int) -> None:
    name = ".high-water.pending"
    data = canonical_json({"schema": HIGH_WATER_SCHEMA, "unix_seconds": now})
    created = _write_exclusive(root_fd, name, data, "high-water")
    renamed = False
    try:
        os.rename(name, "high-water.json", src_dir_fd=root_fd, dst_dir_fd=root_fd)
        renamed = True
        os.fsync(root_fd)
    except Exception:
        if not renamed:
            # A failed rename may leave the exclusive temporary inode behind.
            # Remove only that inode; preserve any concurrent replacement.  If
            # rename committed but directory fsync failed, keep the destination
            # and fail closed rather than deleting a possibly durable update.
            try:
                _unlink_if_inode(root_fd, name, created, strict=False)
            except OSError:
                pass
        raise


def _read_named(root_fd: int, name: str, label: str, *, missing: bool = False) -> Optional[tuple[bytes, os.stat_result]]:
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=root_fd)
    except FileNotFoundError:
        if missing:
            return None
        raise Refused(label + "-missing")
    try:
        st = os.fstat(fd)
        _validate_file(st, label)
        if st.st_size <= 0 or st.st_size > MAX_RECORD_BYTES:
            raise Refused("invalid-" + label)
        chunks: list[bytes] = []
        remaining = st.st_size
        while remaining:
            chunk = os.read(fd, min(4096, remaining))
            if not chunk:
                raise Refused("invalid-" + label)
            chunks.append(chunk)
            remaining -= len(chunk)
        if os.read(fd, 1):
            raise Refused("invalid-" + label)
        held = _verify_named(root_fd, name, fd, label)
        return b"".join(chunks), held
    finally:
        os.close(fd)


def _open_root(path: str) -> _OpenedRoot:
    if type(path) is not str or not path.startswith("/") or path == "/" or path.endswith("/"):
        raise Refused("invalid-state-root")
    parts = path.split("/")[1:]
    if any(part in ("", ".", "..") for part in parts):
        raise Refused("invalid-state-root")
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        for part in parts:
            nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                          dir_fd=fd)
            os.close(fd)
            fd = nxt
        st = os.fstat(fd)
        if (not stat.S_ISDIR(st.st_mode) or st.st_uid != os.geteuid()
                or stat.S_IMODE(st.st_mode) != 0o700 or st.st_nlink < 1):
            raise Refused("unsafe-state-root")
        return _OpenedRoot(fd, st.st_dev, st.st_ino)
    except Exception:
        os.close(fd)
        raise


def _open_lock(root: _OpenedRoot) -> int:
    flags = os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC
    created = False
    fd: Optional[int] = None
    created_identity: Optional[os.stat_result] = None
    complete = False
    try:
        try:
            fd = os.open(LOCK_NAME, flags | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=root.fd)
            created = True
        except FileExistsError:
            fd = os.open(LOCK_NAME, flags, dir_fd=root.fd)
        if created:
            created_identity = os.fstat(fd)
            os.fchmod(fd, 0o600)
            created_identity = os.fstat(fd)
        _validate_file(os.fstat(fd), "lock")
        fcntl.flock(fd, fcntl.LOCK_EX)
        _verify_named(root.fd, LOCK_NAME, fd, "lock")
        current = os.fstat(root.fd)
        if (current.st_dev, current.st_ino) != (root.dev, root.ino):
            raise Refused("state-root-replaced")
        if created:
            os.fsync(root.fd)
        complete = True
        return fd
    finally:
        if not complete and fd is not None:
            if created and created_identity is None:
                try:
                    created_identity = os.fstat(fd)
                except Exception:
                    created_identity = None
            try:
                os.close(fd)
            except OSError:
                pass
            # A lock opened without O_EXCL pre-existed and is never removed.
            if created and created_identity is not None:
                try:
                    _unlink_if_inode(root.fd, LOCK_NAME, created_identity, strict=False)
                except OSError:
                    pass


def _list_names(root_fd: int) -> list[str]:
    try:
        scan = os.open(".", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                       dir_fd=root_fd)
    except Exception as exc:
        raise Refused("state-scan-failed") from exc
    iterator: Any = None
    names: list[str] = []
    try:
        try:
            a, b = os.fstat(root_fd), os.fstat(scan)
        except Exception as exc:
            raise Refused("state-scan-failed") from exc
        if (a.st_dev, a.st_ino) != (b.st_dev, b.st_ino):
            raise Refused("state-scan-replaced")
        try:
            iterator = os.scandir(scan)
            for entry in iterator:
                if len(names) >= MAX_STATE_ENTRIES:
                    raise Refused("state-entry-budget-exhausted")
                name = entry.name
                if type(name) is not str:
                    raise Refused("invalid-state-entry")
                names.append(name)
        except Refused:
            raise
        except Exception as exc:
            raise Refused("state-scan-failed") from exc
        return sorted(names)
    finally:
        if iterator is not None:
            try:
                iterator.close()
            except Exception:
                pass
        try:
            os.close(scan)
        except OSError:
            pass


def _high_water(root_fd: int, now: int) -> None:
    item = _read_named(root_fd, "high-water.json", "high-water", missing=True)
    if item is not None:
        value = _strict_json(item[0], 1024, "invalid-high-water")
        if (type(value) is not dict or set(value) != {"schema", "unix_seconds"}
                or value["schema"] != HIGH_WATER_SCHEMA or type(value["unix_seconds"]) is not int
                or value["unix_seconds"] < 0):
            raise Refused("invalid-high-water")
        if now < value["unix_seconds"]:
            raise Refused("high-water-rollback")
    _replace_high_water(root_fd, now)


def _validate_request(value: Any, request_id: str) -> dict[str, Any]:
    keys = {"schema", "request_id", "nonce", "status", "description", "target_sha256",
            "operation", "scope", "actor_sha256", "issued_at_unix_seconds",
            "expires_at_unix_seconds", "boundaries", "prompt_text_sha256"}
    if type(value) is not dict or set(value) != keys or value.get("schema") != REQUEST_SCHEMA:
        raise Refused("invalid-request")
    if value.get("request_id") != request_id or not re.fullmatch(r"[0-9a-f]{32}", value.get("nonce", "")):
        raise Refused("invalid-request")
    if value.get("status") != "pending" or value.get("operation") != OPERATION or value.get("boundaries") != BOUNDARIES:
        raise Refused("invalid-request")
    _strict_description(value.get("description"))
    _strict_hex64(value.get("target_sha256"), "invalid-request")
    _strict_hex64(value.get("actor_sha256"), "invalid-request")
    _strict_hex64(value.get("prompt_text_sha256"), "invalid-request")
    scope = value.get("scope")
    expected_scope = {"platform_sha256", "chat_id_sha256", "thread_id_sha256", "guild_id_sha256", "parent_chat_id_sha256"}
    if type(scope) is not dict or set(scope) != expected_scope:
        raise Refused("invalid-request")
    for digest in scope.values():
        _strict_hex64(digest, "invalid-request")
    issued, expiry = value.get("issued_at_unix_seconds"), value.get("expires_at_unix_seconds")
    if type(issued) is not int or type(expiry) is not int or not 1 <= expiry - issued <= MAX_TTL:
        raise Refused("invalid-request")
    return value


def _validate_evidence(value: Any, request_sha: str) -> dict[str, Any]:
    keys = {"schema", "disposition", "request_sha256", "actor_sha256", "scope",
            "target_sha256", "prompt_text_sha256", "response_message_sha256",
            "reply_to_message_sha256", "observed_unix_seconds", "operation", "boundaries"}
    if (type(value) is not dict or set(value) != keys or value.get("schema") != EVIDENCE_SCHEMA
            or value.get("disposition") != "NON_AUTHORITATIVE_SHADOW_EVIDENCE"
            or value.get("request_sha256") != request_sha or value.get("operation") != OPERATION
            or value.get("boundaries") != BOUNDARIES):
        raise Refused("invalid-evidence")
    for key in ("request_sha256", "actor_sha256", "target_sha256", "prompt_text_sha256",
                "response_message_sha256", "reply_to_message_sha256"):
        _strict_hex64(value.get(key), "invalid-evidence")
    if type(value.get("observed_unix_seconds")) is not int or value["observed_unix_seconds"] < 0:
        raise Refused("invalid-evidence")
    scope = value.get("scope")
    if type(scope) is not dict or set(scope) != {"platform_sha256", "chat_id_sha256", "thread_id_sha256", "guild_id_sha256", "parent_chat_id_sha256"}:
        raise Refused("invalid-evidence")
    for digest in scope.values():
        _strict_hex64(digest, "invalid-evidence")
    return value


def _sweep(root_fd: int, now: int) -> tuple[list[tuple[str, dict[str, Any], bytes, os.stat_result]], dict[str, dict[str, Any]]]:
    names = _list_names(root_fd)
    allowed_fixed = {LOCK_NAME, "high-water.json"}
    requests: list[tuple[str, dict[str, Any], bytes, os.stat_result]] = []
    evidence: dict[str, dict[str, Any]] = {}
    for name in names:
        match_r, match_e = REQUEST_RE.fullmatch(name), EVIDENCE_RE.fullmatch(name)
        if match_r:
            item = _read_named(root_fd, name, "request")
            assert item is not None
            value = _validate_request(_strict_json(item[0], MAX_RECORD_BYTES, "invalid-request"), match_r.group(1))
            requests.append((name, value, item[0], item[1]))
        elif match_e:
            item = _read_named(root_fd, name, "evidence")
            assert item is not None
            value = _validate_evidence(_strict_json(item[0], MAX_RECORD_BYTES, "invalid-evidence"), match_e.group(1))
            evidence[match_e.group(1)] = value
        elif name not in allowed_fixed:
            raise Refused("unknown-state-entry")
    # Raw requests are removed when expired or already evidenced. Cleanup is inode-bound.
    retained = []
    for row in requests:
        request_sha = hashlib.sha256(row[2]).hexdigest()
        if row[1]["expires_at_unix_seconds"] < now or request_sha in evidence:
            _unlink_if_inode(root_fd, row[0], row[3], strict=True)
        else:
            retained.append(row)
    # Evidence has an age and count budget; oldest is removed safely.
    ordered = sorted(evidence.items(), key=lambda pair: (pair[1]["observed_unix_seconds"], pair[0]))
    remove = {sha for sha, value in ordered if now - value["observed_unix_seconds"] > MAX_EVIDENCE_AGE}
    survivors = [pair for pair in ordered if pair[0] not in remove]
    if len(survivors) > MAX_EVIDENCE:
        remove.update(sha for sha, _ in survivors[:len(survivors) - MAX_EVIDENCE])
    for sha in remove:
        name = "evidence-" + sha + ".json"
        item = _read_named(root_fd, name, "evidence", missing=True)
        if item is not None:
            _unlink_if_inode(root_fd, name, item[1], strict=True)
        evidence.pop(sha, None)
    return retained, evidence


def _render_prompt(record: Mapping[str, Any], expiry_seconds: int) -> str:
    description = json.dumps(record["description"], ensure_ascii=False, separators=(",", ":"))
    description = description.replace("\u0085", "\\u0085").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
    marker = f"[HERMES-SHADOW-APPROVAL-V1 request={record['request_id']} nonce={record['nonce']}]"
    return "\n".join([
        "SHADOW APPROVAL REQUEST — NO ACTION",
        "This is an OFFLINE synthetic/no-op shadow request only.",
        "Replying OK cannot authorize, execute, send, mutate, or prove any real action.",
        f"Description (strict JSON): {description}",
        f"Target SHA-256: {record['target_sha256']}",
        f"Trusted expiry: Unix second {record['expires_at_unix_seconds']} (bounded TTL {expiry_seconds}s)",
        'Operation: {"actionable":false,"kind":"synthetic_noop"}',
        "Proof/action boundaries: identity=false; owner_approval=false; authorization=false; action_executed=false; semantic_proof=false; actionable=false.",
        "Ordinary use: HOLD. Shared default rollout: HOLD.",
        "If you choose to reply, use plain OK; this remains SHADOW / NO ACTION.",
        marker,
    ])


class UnifiedShadowPlane:
    """Combines current-turn issuance and exact reply consumption without action."""

    def __init__(self, config: PlaneConfig):
        if not isinstance(config, PlaneConfig):
            raise TypeError("config must be PlaneConfig")
        _strict_hex64(config.owner_actor_sha256, "invalid-owner-digest")
        if _canonical_discord_id(config.approval_chat_id) is None:
            raise ValueError("approval_chat_id is invalid")
        for value in (config.approval_thread_id, config.approval_guild_id,
                      config.approval_parent_chat_id):
            if value is not None and _canonical_discord_id(value) is None:
                raise ValueError("optional approval scope is invalid")
        if type(config.max_scopes) is not int or not 1 <= config.max_scopes <= 1024:
            raise ValueError("max_scopes is invalid")
        if type(config.scope_ttl_monotonic) not in (int, float) or not 0 < config.scope_ttl_monotonic <= 60:
            raise ValueError("scope_ttl_monotonic is invalid")
        self._config = config
        self._memory_lock = threading.Lock()
        self._scopes: dict[str, _TurnScope] = {}
        self._session_store: Any = None

    def _configured_scope_matches(self, scope: _TurnScope) -> bool:
        return (
            scope.platform == "discord"
            and scope.chat_id == self._config.approval_chat_id
            and scope.thread_id == self._config.approval_thread_id
            and scope.guild_id == self._config.approval_guild_id
            and scope.parent_chat_id == self._config.approval_parent_chat_id
        )

    def pre_llm_call(self, *, session_id: Any = None, current_source_present: Any = False,
                     current_source_valid: Any = False, current_source_platform: Any = "",
                     current_source_user_id: Any = "", current_source_chat_id: Any = "",
                     current_source_thread_id: Any = "", current_source_guild_id: Any = "",
                     current_source_parent_chat_id: Any = "", **_legacy: Any) -> None:
        if type(session_id) is not str or not session_id:
            return
        with self._memory_lock:
            self._scopes.pop(session_id, None)
        if current_source_present is not True or current_source_valid is not True:
            return
        try:
            if current_source_platform != "discord":
                raise Refused("invalid-current-source")
            user_id = _canonical_discord_id(current_source_user_id)
            chat_id = _canonical_discord_id(current_source_chat_id)
            if user_id is None or chat_id is None:
                raise Refused("invalid-current-source")
            parsed = _TurnScope(
                deadline=0.0, platform="discord", user_id=user_id, chat_id=chat_id,
                thread_id=_optional_w45(current_source_thread_id),
                guild_id=_optional_w45(current_source_guild_id),
                parent_chat_id=_optional_w45(current_source_parent_chat_id),
            )
            if not self._configured_scope_matches(parsed):
                raise Refused("outside-configured-scope")
        except Exception:
            return
        with self._memory_lock:
            try:
                now = float(self._config.monotonic_provider())
            except Exception:
                # Fixed fail-closed behavior: no new slot and no payload.
                self._scopes.pop(session_id, None)
                return
            # Capacity applies only to live scopes.  Pruning and admission are
            # one atomic memory-plane operation.
            for key, value in tuple(self._scopes.items()):
                if value.deadline < now:
                    self._scopes.pop(key, None)
            if session_id not in self._scopes and len(self._scopes) >= self._config.max_scopes:
                return
            self._scopes[session_id] = _TurnScope(
                deadline=now + float(self._config.scope_ttl_monotonic),
                platform=parsed.platform, user_id=parsed.user_id, chat_id=parsed.chat_id,
                thread_id=parsed.thread_id, guild_id=parsed.guild_id,
                parent_chat_id=parsed.parent_chat_id,
            )

    def _routing_matches(self, entry: Any, scope: _TurnScope) -> bool:
        try:
            origin = entry.origin
            return (
                _platform(origin.platform) == scope.platform
                and origin.chat_id == scope.chat_id
                and origin.thread_id == scope.thread_id
                and origin.guild_id == scope.guild_id
                and origin.parent_chat_id == scope.parent_chat_id
            )
        except Exception:
            return False

    def issue(self, description: Any, target_sha256: Any, expiry_seconds: Any, *, session_id: Any) -> dict[str, Any]:
        description = _strict_description(description)
        target_sha256 = _strict_hex64(target_sha256, "invalid-target")
        expiry_seconds = _strict_expiry(expiry_seconds)
        if type(session_id) is not str or not session_id:
            raise Refused("missing-session")
        store = self._session_store
        if store is None:
            raise Refused("missing-session-store")
        try:
            entry = store.lookup_by_session_id(session_id)
        except Exception as exc:
            raise Refused("session-lookup-failed") from exc
        if entry is None:
            raise Refused("unknown-session")
        with self._memory_lock:
            scope = self._scopes.get(session_id)
            if scope is None:
                raise Refused("missing-current-turn-scope")
            try:
                fresh = float(self._config.monotonic_provider()) <= scope.deadline
            except Exception as exc:
                self._scopes.pop(session_id, None)
                raise Refused("monotonic-unavailable") from exc
            if not fresh or not self._routing_matches(entry, scope):
                self._scopes.pop(session_id, None)
                raise Refused("stale-or-mismatched-scope")
            observed_actor = actor_digest(scope.platform, scope.user_id)
            if not hmac.compare_digest(observed_actor, self._config.owner_actor_sha256):
                self._scopes.pop(session_id, None)
                raise Refused("actor-mismatch")
            # One-shot authority is consumed before any persistent state access.
            self._scopes.pop(session_id, None)
        now = _sample(self._config.time_provider)
        request_id = _random_hex(self._config.random_provider)
        nonce = _random_hex(self._config.random_provider)
        core = {
            "schema": REQUEST_SCHEMA, "request_id": request_id, "nonce": nonce,
            "status": "pending", "description": description, "target_sha256": target_sha256,
            "operation": dict(OPERATION), "scope": _scope_digests(scope),
            "actor_sha256": observed_actor, "issued_at_unix_seconds": now,
            "expires_at_unix_seconds": now + expiry_seconds, "boundaries": dict(BOUNDARIES),
        }
        prompt = _render_prompt(core, expiry_seconds)
        prompt_bytes = prompt.encode("utf-8", errors="strict")
        if len(prompt_bytes) > MAX_PROMPT_BYTES:
            raise Refused("prompt-too-large")
        record = {**core, "prompt_text_sha256": hashlib.sha256(prompt_bytes).hexdigest()}
        root = _open_root(self._config.state_root)
        try:
            with _PROCESS_LOCK:
                lock = _open_lock(root)
                try:
                    locked_now = _sample(self._config.time_provider)
                    if locked_now < now:
                        raise Refused("trusted-time-rollback")
                    _high_water(root.fd, locked_now)
                    pending, evidence = _sweep(root.fd, locked_now)
                    if len(pending) >= MAX_PENDING or len(evidence) >= MAX_EVIDENCE:
                        raise Refused("state-budget-exhausted")
                    for _name, existing, _raw, _st in pending:
                        if existing["scope"] == record["scope"]:
                            raise Refused("active-request")
                    _write_exclusive(root.fd, "request-" + request_id + ".json",
                                     canonical_json(record), "request")
                finally:
                    fcntl.flock(lock, fcntl.LOCK_UN)
                    os.close(lock)
        finally:
            os.close(root.fd)
        return boundary_result("issued", "synthetic-noop-prompt-created", success=True, prompt=prompt)

    def _event_routing(self, event: Any) -> tuple[str, Optional[_TurnScope], Any]:
        """Classify configured routing without consulting the actor field."""
        try:
            source = event.source
            raw_platform = source.platform
            platform = getattr(raw_platform, "value", raw_platform)
        except Exception:
            return "ambiguous", None, None
        if type(platform) is not str:
            return "ambiguous", None, None
        if platform != "discord":
            return "outside", None, None
        try:
            raw_chat = source.chat_id
        except Exception:
            return "ambiguous", None, None
        chat = _canonical_discord_id(raw_chat)
        if chat is None:
            return "ambiguous", None, None
        if chat != self._config.approval_chat_id:
            return "outside", None, None
        parsed_optional: list[Optional[str]] = []
        for name, expected in (
            ("thread_id", self._config.approval_thread_id),
            ("guild_id", self._config.approval_guild_id),
            ("parent_chat_id", self._config.approval_parent_chat_id),
        ):
            try:
                parsed = _optional_event_id(getattr(source, name))
            except Exception:
                return "ambiguous", None, None
            if parsed != expected:
                return "outside", None, None
            parsed_optional.append(parsed)
        try:
            actor_value = source.user_id
        except Exception:
            actor_value = None
        return "inside", _TurnScope(
            0.0, "discord", "", chat,
            parsed_optional[0], parsed_optional[1], parsed_optional[2],
        ), actor_value

    def pre_gateway_dispatch(self, event: Any, *, session_store: Any = None, **_kwargs: Any) -> dict[str, Any]:
        if session_store is not None:
            try:
                lookup = getattr(session_store, "lookup_by_session_id")
            except Exception:
                lookup = None
            if callable(lookup):
                self._session_store = session_store
        try:
            text = event.text
            text_failed = False
        except Exception:
            text = None
            text_failed = True
        if not text_failed and not (type(text) is str and text.strip(" \t\r\n") == "OK"):
            return boundary_result("allow", "not-approval-text")

        routing, partial, actor_value = self._event_routing(event)
        if routing == "outside":
            return boundary_result("allow", "outside-approval-scope")
        if routing != "inside" or partial is None or text_failed:
            return boundary_result("skip", "internal-refusal")

        user_id = _canonical_discord_id(actor_value)
        if user_id is None:
            return boundary_result("skip", "approval-actor-mismatch")
        observed_actor = actor_digest(partial.platform, user_id)
        if not hmac.compare_digest(observed_actor, self._config.owner_actor_sha256):
            return boundary_result("skip", "approval-actor-mismatch")
        incoming_scope = _TurnScope(
            0.0, partial.platform, user_id, partial.chat_id,
            partial.thread_id, partial.guild_id, partial.parent_chat_id,
        )
        try:
            return self._consume(event, incoming_scope, observed_actor)
        except Refused as exc:
            return boundary_result("skip", str(exc))
        except Exception:
            return boundary_result("skip", "internal-refusal")

    def _consume(self, event: Any, scope: _TurnScope, observed_actor: str) -> dict[str, Any]:
        if type(getattr(event, "media_urls", None)) is not list or type(getattr(event, "media_types", None)) is not list:
            raise Refused("missing-media-capability")
        if event.media_urls or event.media_types:
            raise Refused("media-forbidden")
        if getattr(event, "internal", None) is not False:
            raise Refused("internal-event-forbidden")
        # Discord history backfill is untrusted ambient context, not an
        # approval input.  Ignore it completely; all authority-relevant data
        # remains bound to the exact event text, authenticated native reply,
        # prompt digest, actor, and route below.
        if getattr(event, "reply_to_is_own_message", None) is not True:
            raise Refused("reply-target-not-bot-authenticated")
        response_id = _canonical_discord_id(getattr(event, "message_id", None))
        reply_id = _canonical_discord_id(getattr(event, "reply_to_message_id", None))
        reply_text = getattr(event, "reply_to_text", None)
        if response_id is None or reply_id is None or type(reply_text) is not str:
            raise Refused("invalid-reply-capability")
        try:
            prompt_bytes = reply_text.encode("utf-8", errors="strict")
        except UnicodeError as exc:
            raise Refused("invalid-reply-text") from exc
        if len(prompt_bytes) > MAX_PROMPT_BYTES:
            raise Refused("invalid-reply-text")
        marker = MARKER_RE.search(reply_text)
        if marker is None or marker.end() != len(reply_text) or (marker.start() and reply_text[marker.start()-1] != "\n"):
            raise Refused("invalid-final-marker")
        request_id, nonce = marker.groups()
        now = _sample(self._config.time_provider)
        root = _open_root(self._config.state_root)
        try:
            with _PROCESS_LOCK:
                lock = _open_lock(root)
                try:
                    locked_now = _sample(self._config.time_provider)
                    if locked_now < now:
                        raise Refused("trusted-time-rollback")
                    _high_water(root.fd, locked_now)
                    pending, evidence = _sweep(root.fd, locked_now)
                    selected = next((row for row in pending if row[1]["request_id"] == request_id), None)
                    if selected is None:
                        raise Refused("unknown-or-consumed-request")
                    name, request, raw_request, held = selected
                    request_sha = hashlib.sha256(raw_request).hexdigest()
                    if request_sha in evidence:
                        _unlink_if_inode(root.fd, name, held, strict=True)
                        raise Refused("request-replay")
                    if request["nonce"] != nonce:
                        raise Refused("nonce-mismatch")
                    if locked_now < request["issued_at_unix_seconds"]:
                        raise Refused("request-from-future")
                    if locked_now > request["expires_at_unix_seconds"]:
                        _unlink_if_inode(root.fd, name, held, strict=True)
                        raise Refused("request-expired")
                    if request["actor_sha256"] != observed_actor or request["scope"] != _scope_digests(scope):
                        raise Refused("request-scope-mismatch")
                    prompt_sha = hashlib.sha256(prompt_bytes).hexdigest()
                    if request["prompt_text_sha256"] != prompt_sha:
                        raise Refused("prompt-digest-mismatch")
                    if len(evidence) >= MAX_EVIDENCE:
                        raise Refused("state-budget-exhausted")
                    evidence_record = {
                        "schema": EVIDENCE_SCHEMA,
                        "disposition": "NON_AUTHORITATIVE_SHADOW_EVIDENCE",
                        "request_sha256": request_sha,
                        "actor_sha256": observed_actor,
                        "scope": request["scope"],
                        "target_sha256": request["target_sha256"],
                        "prompt_text_sha256": prompt_sha,
                        "response_message_sha256": hashlib.sha256(b"discord-response-v1\x00" + response_id.encode("ascii")).hexdigest(),
                        "reply_to_message_sha256": hashlib.sha256(b"discord-reply-target-v1\x00" + reply_id.encode("ascii")).hexdigest(),
                        "observed_unix_seconds": locked_now,
                        "operation": dict(OPERATION),
                        "boundaries": dict(BOUNDARIES),
                    }
                    try:
                        _write_exclusive(root.fd, "evidence-" + request_sha + ".json",
                                         canonical_json(evidence_record), "evidence")
                    except FileExistsError as exc:
                        raise Refused("request-replay") from exc
                    # Evidence is durable before raw request cleanup.
                    _unlink_if_inode(root.fd, name, held, strict=True)
                finally:
                    fcntl.flock(lock, fcntl.LOCK_UN)
                    os.close(lock)
        finally:
            os.close(root.fd)
        return boundary_result("skip", "non-actionable-evidence-recorded")
