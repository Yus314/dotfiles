"""Overlay declarative TOML settings without discarding runtime-owned keys.

Run while the application is not saving settings. Atomic replacement prevents
partial reads, but applications do not share a writer lock with Home Manager.
"""

import argparse
import os
import tempfile
from collections.abc import MutableMapping
from pathlib import Path

import tomlkit


def merge(target, managed):
    for key, value in managed.items():
        if isinstance(value, MutableMapping) and isinstance(
            target.get(key), MutableMapping
        ):
            merge(target[key], value)
        else:
            target[key] = value


def materialize(source: Path, target: Path):
    managed = tomlkit.parse(source.read_text())
    present = target.exists() or target.is_symlink()
    original = target.read_bytes() if present else None
    document = (
        tomlkit.parse(original.decode()) if original is not None else tomlkit.document()
    )
    merge(document, managed)
    result = tomlkit.dumps(document).encode()
    if original == result and not target.is_symlink():
        target.chmod(0o600)
        return

    target.parent.mkdir(parents=True, exist_ok=True)
    # A private backup preserves the exact pre-migration/pre-update contents.
    if original is not None:
        fd, _backup = tempfile.mkstemp(
            prefix=target.name + ".backup-", dir=target.parent
        )
        with os.fdopen(fd, "wb") as stream:
            stream.write(original)

    fd, temporary = tempfile.mkstemp(prefix="." + target.name + "-", dir=target.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(result)
            stream.flush()
            os.fsync(stream.fileno())
        # Fail rather than knowingly clobbering a concurrent settings update.
        current = (
            target.read_bytes() if target.exists() or target.is_symlink() else None
        )
        if current != original:
            raise RuntimeError(
                "Configuration changed during activation; retry with settings idle"
            )
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path)
    args = parser.parse_args()
    materialize(args.source, args.target)
