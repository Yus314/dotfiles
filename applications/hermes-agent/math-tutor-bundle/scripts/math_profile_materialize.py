#!/usr/bin/env python3
"""Materialize an immutable math candidate into an isolated profile fixture only."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import tempfile
from pathlib import Path

import yaml

MANAGED_SKILL_RELATIVE = Path("skills/parity-study")


def sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def atomic_write(path: Path, content: bytes, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def verify_candidate(candidate: Path) -> dict:
    if candidate.is_symlink() or not candidate.is_dir():
        raise ValueError("candidate must be a regular directory, not a symlink")
    symlinks = [path.relative_to(candidate).as_posix() for path in candidate.rglob("*") if path.is_symlink()]
    if symlinks:
        raise ValueError(f"candidate must not contain symlinks: {sorted(symlinks)}")
    metadata = json.loads((candidate / "candidate-metadata.json").read_text())
    mismatches = []
    for relative, expected in metadata["effective_file_digests"].items():
        path = candidate / relative
        actual = sha256_bytes(path.read_bytes()) if path.is_file() else "missing"
        if actual != expected:
            mismatches.append(relative)
    if mismatches:
        raise ValueError(f"candidate effective digest mismatch: {mismatches}")
    expected = sorted(item["name"] for item in metadata["skill_allowlist"])
    actual = sorted(
        path.name for path in (candidate / "skills/study").iterdir() if path.is_dir()
    )
    if actual != expected:
        raise ValueError(f"candidate skill package set mismatch: expected={expected} actual={actual}")
    return metadata


def ensure_fixture_root(profile_root: Path) -> None:
    root = profile_root.resolve(strict=False)
    production = (Path.home() / ".hermes").resolve(strict=False)
    try:
        root.relative_to(production)
    except ValueError:
        pass
    else:
        raise ValueError(
            "fixture-only materializer refuses a profile below the active ~/.hermes tree"
        )
    marker = profile_root / ".math-parity-fixture"
    if marker.is_symlink() or not marker.is_file():
        raise ValueError(
            "fixture-only materializer requires a regular .math-parity-fixture marker"
        )


def ensure_managed_paths_are_bounded(profile_root: Path) -> None:
    """Reject existing symlink components on every path the materializer may touch."""
    for relative in (
        Path("config.yaml"),
        Path("SOUL.md"),
        Path("honcho.json"),
        Path(".parity"),
        Path("skills"),
        MANAGED_SKILL_RELATIVE,
    ):
        current = profile_root
        for part in relative.parts:
            current = current / part
            if current.is_symlink():
                raise ValueError(f"managed path must not contain symlinks: {current}")


def load_config(path: Path) -> dict:
    if not path.exists():
        return {}
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"config must be a regular non-symlink file: {path}")
    loaded = yaml.safe_load(path.read_text(encoding="utf-8"))
    if loaded is None:
        return {}
    if not isinstance(loaded, dict):
        raise ValueError("profile config must be a mapping")
    return loaded


def merged_config(current: dict, fragment: dict, managed_root: Path) -> dict:
    result = dict(current)
    model = result.get("model")
    if not isinstance(model, dict):
        model = {}
    result["model"] = {**model, **fragment["model"]}

    terminal = result.get("terminal")
    if not isinstance(terminal, dict):
        terminal = {}
    result["terminal"] = {**terminal, "cwd": fragment["terminal"]["cwd"]}

    skills = result.get("skills")
    if not isinstance(skills, dict):
        skills = {}
    external = skills.get("external_dirs", [])
    if not isinstance(external, list) or any(not isinstance(item, str) for item in external):
        raise ValueError("skills.external_dirs must be a string list")
    managed = str(managed_root)
    unmanaged = [item for item in external if item != managed]
    result["skills"] = {**skills, "external_dirs": [managed, *unmanaged]}
    memory = result.get("memory")
    if not isinstance(memory, dict):
        memory = {}
    result["memory"] = {**memory, **fragment["memory"]}
    return result


def rendered_yaml(value: dict) -> bytes:
    return yaml.safe_dump(value, sort_keys=False, allow_unicode=True).encode("utf-8")


def desired_files(candidate: Path, profile_root: Path, config: dict) -> dict[Path, tuple[bytes, int]]:
    files: dict[Path, tuple[bytes, int]] = {
        profile_root / "config.yaml": (rendered_yaml(config), 0o600),
        profile_root / "SOUL.md": ((candidate / "SOUL.md").read_bytes(), 0o644),
        profile_root / "honcho.json": ((candidate / "honcho.json").read_bytes(), 0o600),
        profile_root / ".parity/candidate-metadata.json": (
            (candidate / "candidate-metadata.json").read_bytes(),
            0o644,
        ),
    }
    source = candidate / "skills/study"
    for path in sorted(item for item in source.rglob("*") if item.is_file()):
        relative = path.relative_to(source)
        files[profile_root / MANAGED_SKILL_RELATIVE / relative] = (
            path.read_bytes(),
            0o644,
        )
    return files


def build_plan(candidate: Path, profile_root: Path) -> tuple[dict, dict[Path, tuple[bytes, int]]]:
    metadata = verify_candidate(candidate)
    ensure_fixture_root(profile_root)
    ensure_managed_paths_are_bounded(profile_root)
    fragment = json.loads((candidate / "config.fragment.json").read_text())
    current = load_config(profile_root / "config.yaml")
    managed_root = (profile_root / MANAGED_SKILL_RELATIVE).resolve(strict=False)
    config = merged_config(current, fragment, managed_root)
    desired = desired_files(candidate, profile_root, config)
    changes = []
    for path, (content, mode) in sorted(desired.items(), key=lambda item: str(item[0])):
        current_content = path.read_bytes() if path.is_file() else None
        current_mode = (path.stat().st_mode & 0o777) if path.is_file() else None
        if current_content == content and current_mode == mode:
            action = "unchanged"
        else:
            action = "update" if path.exists() else "create"
        changes.append(
            {
                "path": path.relative_to(profile_root).as_posix(),
                "action": action,
                "sha256": sha256_bytes(content),
                "mode": f"{mode:04o}",
            }
        )
    expected_managed = {
        path.relative_to(profile_root).as_posix()
        for path in desired
        if path.is_relative_to(profile_root / MANAGED_SKILL_RELATIVE)
    }
    managed_root_path = profile_root / MANAGED_SKILL_RELATIVE
    stale = []
    if managed_root_path.is_dir():
        for path in managed_root_path.rglob("*"):
            if path.is_file() and path.relative_to(profile_root).as_posix() not in expected_managed:
                stale.append(path.relative_to(profile_root).as_posix())
    for path in sorted(stale):
        changes.append({"path": path, "action": "remove-managed-stale"})
    plan = {
        "schema_version": 1,
        "mode": "dry-run",
        "candidate_digest": metadata["bundle_aggregate_sha256"],
        "profile_root_kind": "isolated-fixture",
        "changes": changes,
        "preserves_unmanaged_config": True,
        "preserves_unmanaged_skill_roots": True,
        "honcho_materialized": True,
        "credentials_materialized": False,
        "activation_performed": False,
        "gateway_restarted": False,
    }
    return plan, desired


def apply_plan(
    profile_root: Path,
    desired: dict[Path, tuple[bytes, int]],
) -> None:
    managed_root = profile_root / MANAGED_SKILL_RELATIVE
    source_entries = {
        path.relative_to(managed_root): (content, mode)
        for path, (content, mode) in desired.items()
        if path.is_relative_to(managed_root)
    }
    managed_root.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        dir=managed_root.parent, prefix=".parity-study-new-"
    ) as name:
        temporary_root = Path(name)
        for relative, (content, mode) in source_entries.items():
            atomic_write(temporary_root / relative, content, mode)
        backup: Path | None = None
        try:
            if managed_root.exists():
                backup = Path(
                    tempfile.mkdtemp(dir=managed_root.parent, prefix=".parity-study-old-")
                )
                backup.rmdir()
                os.replace(managed_root, backup)
            os.replace(temporary_root, managed_root)
        except Exception:
            if backup is not None and backup.exists() and not managed_root.exists():
                os.replace(backup, managed_root)
            raise
        finally:
            if backup is not None and backup.exists():
                shutil.rmtree(backup)
    for path, (content, mode) in desired.items():
        if path.is_relative_to(managed_root):
            continue
        atomic_write(path, content, mode)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--profile-root", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")

    args = parser.parse_args()
    try:
        plan, desired = build_plan(args.candidate.resolve(), args.profile_root.resolve())
        if args.apply:
            apply_plan(args.profile_root.resolve(), desired)
            plan["mode"] = "applied-fixture-only"
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError, yaml.YAMLError) as error:
        print(json.dumps({"schema_version": 1, "status": "error", "error": str(error)}))
        return 1
    text = json.dumps(plan, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
