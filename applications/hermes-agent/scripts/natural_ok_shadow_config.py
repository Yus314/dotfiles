#!/usr/bin/env python3
"""Safely and idempotently enable the W40 standalone shadow plugin."""
from __future__ import annotations

import fcntl
import os
import secrets
import stat
import sys
from pathlib import Path

import yaml

PLUGIN = "natural-ok-unified-shadow"
MAX_CONFIG_BYTES = 1024 * 1024


def _open_directory(path: Path) -> int:
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("config parent must be lexical absolute")
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts[1:]:
            next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        metadata = os.fstat(fd)
        if metadata.st_uid != os.getuid() or not stat.S_ISDIR(metadata.st_mode):
            raise PermissionError("unsafe config parent")
        return fd
    except BaseException:
        os.close(fd)
        raise


def _verify_private_regular(metadata: os.stat_result) -> None:
    if (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != os.getuid()
        or metadata.st_nlink != 1
        or stat.S_IMODE(metadata.st_mode) != 0o600
    ):
        raise PermissionError("unsafe private file")


def _read_config(directory_fd: int, name: str) -> dict:
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory_fd)
    except FileNotFoundError:
        return {}
    try:
        metadata = os.fstat(fd)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != os.getuid()
            or metadata.st_nlink != 1
            or stat.S_IMODE(metadata.st_mode) not in {0o600, 0o644}
        ):
            raise PermissionError("unsafe config file")
        if metadata.st_size > MAX_CONFIG_BYTES:
            raise ValueError("config exceeds byte budget")
        chunks: list[bytes] = []
        remaining = MAX_CONFIG_BYTES + 1
        while remaining:
            block = os.read(fd, min(65536, remaining))
            if not block:
                break
            chunks.append(block)
            remaining -= len(block)
        raw = b"".join(chunks)
        if len(raw) > MAX_CONFIG_BYTES:
            raise ValueError("config exceeds byte budget")
        after = os.fstat(fd)
        before_projection = (
            metadata.st_dev, metadata.st_ino, metadata.st_mode, metadata.st_uid,
            metadata.st_nlink, metadata.st_size, metadata.st_mtime_ns, metadata.st_ctime_ns,
        )
        after_projection = (
            after.st_dev, after.st_ino, after.st_mode, after.st_uid,
            after.st_nlink, after.st_size, after.st_mtime_ns, after.st_ctime_ns,
        )
        if after_projection != before_projection:
            raise RuntimeError("config changed while reading")
    finally:
        os.close(fd)
    loaded = yaml.safe_load(raw.decode("utf-8"))
    if not isinstance(loaded, dict):
        raise ValueError("Hermes config must be a mapping")
    return loaded


def _unlink_if_same(directory_fd: int, name: str, identity: tuple[int, int]) -> None:
    try:
        current = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        if (current.st_dev, current.st_ino) == identity:
            os.unlink(name, dir_fd=directory_fd)
            os.fsync(directory_fd)
    except FileNotFoundError:
        return


def _recover_identity(fd: int) -> tuple[int, int] | None:
    try:
        metadata = os.fstat(fd)
    except Exception:
        return None
    return (metadata.st_dev, metadata.st_ino)


def _atomic_write(directory_fd: int, name: str, data: bytes) -> None:
    temporary = f".{name}.w49.{os.getpid()}.{secrets.token_hex(8)}.tmp"
    fd = -1
    identity: tuple[int, int] | None = None
    committed = False
    try:
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory_fd)
        metadata = os.fstat(fd)
        identity = (metadata.st_dev, metadata.st_ino)
        os.fchmod(fd, 0o600)
        _verify_private_regular(os.fstat(fd))
        view = memoryview(data)
        while view:
            written = os.write(fd, view)
            if written <= 0:
                raise OSError("zero-progress config write")
            view = view[written:]
        os.fsync(fd)
        bound = os.stat(temporary, dir_fd=directory_fd, follow_symlinks=False)
        if (bound.st_dev, bound.st_ino) != identity:
            raise RuntimeError("temporary config identity changed")
        os.rename(temporary, name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
        committed = True
        os.fsync(directory_fd)
    finally:
        if fd >= 0 and identity is None:
            identity = _recover_identity(fd)
        if fd >= 0:
            os.close(fd)
        if not committed and identity is not None:
            _unlink_if_same(directory_fd, temporary, identity)


def _open_lock(directory_fd: int, name: str) -> int:
    fd = -1
    created = False
    identity: tuple[int, int] | None = None
    try:
        try:
            fd = os.open(
                name,
                os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
                dir_fd=directory_fd,
            )
            created = True
        except FileExistsError:
            fd = os.open(name, os.O_RDWR | os.O_NOFOLLOW, dir_fd=directory_fd)
        metadata = os.fstat(fd)
        identity = (metadata.st_dev, metadata.st_ino)
        if created:
            if (
                not stat.S_ISREG(metadata.st_mode)
                or metadata.st_uid != os.getuid()
                or metadata.st_nlink != 1
            ):
                raise PermissionError("unsafe newly-created lock")
            os.fchmod(fd, 0o600)
            _verify_private_regular(os.fstat(fd))
        else:
            _verify_private_regular(metadata)
        bound = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        if (bound.st_dev, bound.st_ino) != identity:
            raise RuntimeError("lock identity changed")
        fcntl.flock(fd, fcntl.LOCK_EX)
        return fd
    except BaseException:
        if fd >= 0 and identity is None:
            identity = _recover_identity(fd)
        if fd >= 0:
            os.close(fd)
        if created and identity is not None:
            _unlink_if_same(directory_fd, name, identity)
        raise


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in {"--enable", "--disable"}:
        return 2
    operation = sys.argv[1]
    path = Path(sys.argv[2]).expanduser()
    if not path.is_absolute() or path.name in {"", ".", ".."}:
        raise ValueError("config path must be lexical absolute")
    directory_fd = _open_directory(path.parent)
    lock_fd = -1
    try:
        # Validate the complete existing config before creating a missing lock so
        # malformed/symlinked input has no refusal-side file-creation effect.
        _read_config(directory_fd, path.name)
        lock_fd = _open_lock(directory_fd, path.name + ".lock")
        config = _read_config(directory_fd, path.name)
        plugins = config.setdefault("plugins", {})
        if not isinstance(plugins, dict):
            raise ValueError("plugins config must be a mapping")
        enabled = plugins.get("enabled", [])
        if not isinstance(enabled, list) or any(not isinstance(item, str) for item in enabled):
            raise ValueError("plugins.enabled must be a string list")
        normalized = {item for item in enabled if item.strip()}
        if operation == "--enable":
            normalized.add(PLUGIN)
        else:
            normalized.discard(PLUGIN)
        plugins["enabled"] = sorted(normalized)
        payload = yaml.safe_dump(config, sort_keys=False, allow_unicode=True).encode("utf-8")
        if len(payload) > MAX_CONFIG_BYTES:
            raise ValueError("serialized config exceeds byte budget")
        _atomic_write(directory_fd, path.name, payload)
    finally:
        if lock_fd >= 0:
            os.close(lock_fd)
        os.close(directory_fd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
