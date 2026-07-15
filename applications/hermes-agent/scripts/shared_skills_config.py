#!/usr/bin/env python3
"""Configure and verify read-only shared Hermes skills across profiles."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Callable, Iterable

import yaml

SHARED_GROUPS = ("common", "study", "engineering", "orchestration", "profile-ops")
PROFILE_GROUPS: dict[str, tuple[str, ...]] = {
    "default": (
        "common",
        "study",
        "engineering",
        "orchestration",
        "profile-ops",
    ),
    "career": ("common", "study", "engineering", "orchestration"),
    "economics": ("common", "study"),
    "english": ("common", "study", "orchestration"),
    "finance": ("common",),
    "food": ("common",),
    "health": ("common",),
    "indiedev": ("common", "engineering", "orchestration"),
    "math": ("common", "study"),
    "researcheval": ("common", "engineering"),
}
NAME_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
MARKDOWN_LINK_PATTERN = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")
SKILL_COMMAND_INVALID_CHARS = re.compile(r"[^a-z0-9-]")
SKILL_COMMAND_MULTI_HYPHEN = re.compile(r"-{2,}")
DISCORD_COMMAND_NAME_LIMIT = 32
TRANSIENT_ARTIFACT_NAMES = {".manifest.json", "__pycache__"}
TRANSIENT_ARTIFACT_SUFFIXES = {".pyc", ".pyo"}
SECRET_PATTERNS = (
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"\bsk-(?:or-v1-)?[A-Za-z0-9_-]{20,}\b"),
    re.compile(r"\bgh[oprsu]_[A-Za-z0-9]{20,}\b"),
)
SECRET_CAPABILITY_KEYS = {
    "required_environment_variables",
    "required_credential_files",
    "credential_files",
    "environment_variables",
}


@dataclass(frozen=True)
class SkillRecord:
    group: str
    name: str
    path: str
    sha256: str
    package_sha256: str


def profile_config_path(home: Path, profile: str) -> Path:
    if profile == "default":
        return home / ".hermes/config.yaml"
    return home / ".hermes/profiles" / profile / "config.yaml"


def _frontmatter(path: Path) -> dict:
    text = path.read_text()
    if not text.startswith("---\n"):
        raise ValueError(f"missing YAML frontmatter: {path}")
    parts = text.split("---", 2)
    if len(parts) != 3:
        raise ValueError(f"unterminated YAML frontmatter: {path}")
    try:
        loaded = yaml.safe_load(parts[1])
    except yaml.YAMLError as error:
        raise ValueError(f"invalid YAML frontmatter {path}: {error}") from error
    if not isinstance(loaded, dict):
        raise ValueError(f"frontmatter is not a mapping: {path}")
    return loaded


def _walk_values(value, key: str = "") -> Iterable[tuple[str, object]]:
    if isinstance(value, dict):
        for child_key, child_value in value.items():
            normalized = str(child_key).strip().lower()
            yield normalized, child_value
            yield from _walk_values(child_value, normalized)
    elif isinstance(value, list):
        for item in value:
            yield from _walk_values(item, key)


def _has_secret_capability(frontmatter: dict) -> bool:
    for key, value in _walk_values(frontmatter):
        if key in SECRET_CAPABILITY_KEYS and value not in (None, "", [], {}):
            return True
        if key == "env" and value not in (None, "", [], {}):
            return True
    return False


def _skill_command_slug(name: str) -> str:
    slug = name.lower().replace(" ", "-").replace("_", "-")
    slug = SKILL_COMMAND_INVALID_CHARS.sub("", slug)
    return SKILL_COMMAND_MULTI_HYPHEN.sub("-", slug).strip("-")


def _validate_local_links(skill_file: Path, package_root: Path) -> None:
    text = skill_file.read_text()
    for match in MARKDOWN_LINK_PATTERN.finditer(text):
        target = match.group(1).strip().split(maxsplit=1)[0].strip("<>\"'")
        if not target or target.startswith(
            ("#", "http://", "https://", "mailto:", "data:")
        ):
            continue
        target = target.split("#", 1)[0]
        if not target:
            continue
        if target.startswith(("/", "$", "~")):
            raise ValueError(
                f"absolute or environment-dependent local link: {skill_file}: {target}"
            )
        if "<" in target or ">" in target:
            continue
        resolved = (skill_file.parent / target).resolve()
        try:
            resolved.relative_to(package_root.resolve())
        except ValueError as error:
            raise ValueError(
                f"local link escapes skill package: {skill_file}: {target}"
            ) from error
        if not resolved.exists():
            raise ValueError(f"missing local link target: {skill_file}: {target}")


def _validate_shared_tree_security(
    shared_root: Path, *, allow_build_manifest: bool = False
) -> None:
    for path in (shared_root, *shared_root.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"symlink is not allowed in shared skill source: {path}")
        if (
            path.name in TRANSIENT_ARTIFACT_NAMES
            or path.suffix in TRANSIENT_ARTIFACT_SUFFIXES
        ) and not (allow_build_manifest and path == shared_root / ".manifest.json"):
            raise ValueError(
                f"generated or transient artifact in shared skill source: {path}"
            )
        if not path.is_file():
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue
        for pattern in SECRET_PATTERNS:
            if pattern.search(text):
                raise ValueError(f"probable secret in shared skill source: {path}")


def _package_hash(package_root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in package_root.rglob("*") if item.is_file()):
        relative = path.relative_to(package_root).as_posix().encode()
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        content = path.read_bytes()
        digest.update(len(content).to_bytes(8, "big"))
        digest.update(content)
    return digest.hexdigest()


def _validate_package(package_root: Path) -> None:
    for markdown_file in package_root.rglob("*.md"):
        _validate_local_links(markdown_file, package_root)


def validate_source(
    shared_root: Path,
    profile_groups: dict[str, tuple[str, ...]] = PROFILE_GROUPS,
    *,
    allow_build_manifest: bool = False,
) -> list[SkillRecord]:
    shared_root = shared_root.expanduser().resolve()
    if not shared_root.is_dir():
        raise ValueError(f"shared skill root is missing: {shared_root}")

    declared_groups = {group for groups in profile_groups.values() for group in groups}
    unknown_groups = declared_groups - set(SHARED_GROUPS)
    if unknown_groups:
        raise ValueError(
            f"unknown shared skill groups in profile matrix: {sorted(unknown_groups)}"
        )
    missing_groups = sorted(
        group for group in declared_groups if not (shared_root / group).is_dir()
    )
    if missing_groups:
        raise ValueError(f"missing shared skill group directories: {missing_groups}")
    _validate_shared_tree_security(
        shared_root, allow_build_manifest=allow_build_manifest
    )

    records: list[SkillRecord] = []
    names: dict[str, Path] = {}
    command_slugs: dict[str, Path] = {}
    discord_commands: dict[str, tuple[str, Path]] = {}
    for group in sorted(declared_groups):
        group_root = shared_root / group
        unexpected_files = sorted(
            path.name
            for path in group_root.iterdir()
            if path.is_file() and path.name != "README.md"
        )
        if unexpected_files:
            raise ValueError(
                f"unexpected files in shared skill group {group}: {unexpected_files}"
            )
        for package_root in sorted(
            path for path in group_root.iterdir() if path.is_dir()
        ):
            skill_file = package_root / "SKILL.md"
            if not skill_file.is_file():
                raise ValueError(
                    f"shared skill package is missing SKILL.md: {package_root}"
                )
            nested_skill_files = [
                path for path in package_root.rglob("SKILL.md") if path != skill_file
            ]
            if nested_skill_files:
                raise ValueError(
                    f"nested SKILL.md is not allowed in shared package {package_root}"
                )
            frontmatter = _frontmatter(skill_file)
            name = frontmatter.get("name")
            description = frontmatter.get("description")
            if not isinstance(name, str) or not NAME_PATTERN.fullmatch(name):
                raise ValueError(f"invalid shared skill name in {skill_file}: {name!r}")
            if package_root.name != name:
                raise ValueError(
                    "shared skill directory name does not match frontmatter name: "
                    f"{package_root.name!r} != {name!r}: {skill_file}"
                )
            if name in names:
                raise ValueError(
                    f"duplicate skill name {name!r}: {names[name]} and {skill_file}"
                )
            command_slug = _skill_command_slug(name)
            if command_slug in command_slugs:
                raise ValueError(
                    f"normalized slash-command collision {command_slug!r}: "
                    f"{command_slugs[command_slug]} and {skill_file}"
                )
            discord_command = command_slug[:DISCORD_COMMAND_NAME_LIMIT]
            if discord_command in discord_commands:
                previous_name, previous_path = discord_commands[discord_command]
                raise ValueError(
                    f"Discord command collision after {DISCORD_COMMAND_NAME_LIMIT} "
                    f"characters: {previous_name!r} ({previous_path}) and "
                    f"{name!r} ({skill_file})"
                )
            if not isinstance(description, str) or not description.strip():
                raise ValueError(f"missing shared skill description: {skill_file}")
            combined_frontmatter_text = f"{name}{description}"
            if (
                "<" in combined_frontmatter_text
                or ">" in combined_frontmatter_text
                or any(ord(character) < 32 for character in combined_frontmatter_text)
            ):
                raise ValueError(
                    f"unsafe frontmatter text in shared skill: {skill_file}"
                )
            if group == "common" and _has_secret_capability(frontmatter):
                raise ValueError(
                    f"common skill declares a secret capability: {skill_file}"
                )
            _validate_package(package_root)
            names[name] = skill_file
            command_slugs[command_slug] = skill_file
            discord_commands[discord_command] = (name, skill_file)
            records.append(
                SkillRecord(
                    group=group,
                    name=name,
                    path=str(skill_file.resolve()),
                    sha256=hashlib.sha256(skill_file.read_bytes()).hexdigest(),
                    package_sha256=_package_hash(package_root),
                )
            )
    return records


def _discover_profiles(home: Path) -> set[str]:
    profiles: set[str] = set()
    if profile_config_path(home, "default").is_file():
        profiles.add("default")
    profiles_root = home / ".hermes/profiles"
    if profiles_root.is_dir():
        profiles.update(
            path.name
            for path in profiles_root.iterdir()
            if path.is_dir() and (path / "config.yaml").is_file()
        )
    return profiles


def _load_config(path: Path) -> dict:
    if path.is_symlink():
        raise ValueError(f"refusing to replace symlinked Hermes profile config: {path}")
    if not path.is_file():
        raise ValueError(f"missing Hermes profile config: {path}")
    try:
        loaded = yaml.safe_load(path.read_text())
    except yaml.YAMLError as error:
        raise ValueError(f"invalid Hermes profile config {path}: {error}") from error
    if not isinstance(loaded, dict):
        raise ValueError(f"Hermes profile config is not a mapping: {path}")
    return loaded


def _write_yaml_atomic(path: Path, value: dict) -> None:
    rendered = yaml.safe_dump(value, sort_keys=False, allow_unicode=True)
    fd, temporary_name = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", text=True
    )
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


def _managed_paths(shared_root: Path) -> set[str]:
    return {str(shared_root), *(str(shared_root / group) for group in SHARED_GROUPS)}


def _expected_external_dirs(shared_root: Path, groups: tuple[str, ...]) -> list[str]:
    return [str(shared_root / group) for group in groups]


def _check_profile_matrix(
    home: Path,
    profile_groups: dict[str, tuple[str, ...]],
    *,
    require_complete: bool,
) -> None:
    actual = _discover_profiles(home)
    expected = set(profile_groups)
    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)
    if unexpected or (require_complete and missing):
        raise ValueError(
            f"profile matrix drift: missing={missing}, unexpected={unexpected}"
        )


def _logical_absolute(path: Path) -> Path:
    """Return an absolute path without resolving a stable public symlink."""
    return Path(os.path.abspath(path.expanduser()))


def apply(
    home: Path,
    shared_root: Path,
    profile_groups: dict[str, tuple[str, ...]] = PROFILE_GROUPS,
) -> None:
    home = _logical_absolute(home)
    shared_root = _logical_absolute(shared_root)
    validate_source(shared_root, profile_groups, allow_build_manifest=True)
    _check_profile_matrix(home, profile_groups, require_complete=False)
    available_profiles = _discover_profiles(home)

    managed = _managed_paths(shared_root)
    updates: list[tuple[Path, dict]] = []
    for profile, groups in profile_groups.items():
        if profile not in available_profiles:
            continue
        path = profile_config_path(home, profile)
        config = _load_config(path)
        skills = config.get("skills")
        if skills is None:
            skills = {}
            config["skills"] = skills
        elif not isinstance(skills, dict):
            raise ValueError(f"skills config is not a mapping: {path}")
        external_dirs = skills.get("external_dirs", [])
        if not isinstance(external_dirs, list) or any(
            not isinstance(item, str) for item in external_dirs
        ):
            raise ValueError(f"skills.external_dirs is not a string list: {path}")
        unmanaged = [item for item in external_dirs if item not in managed]
        skills["external_dirs"] = [
            *_expected_external_dirs(shared_root, groups),
            *unmanaged,
        ]
        updates.append((path, config))

    for path, config in updates:
        _write_yaml_atomic(path, config)


def _default_cli_runner(profile: str) -> str:
    command = ["hermes"]
    if profile != "default":
        command.extend(["-p", profile])
    command.extend(["skills", "list", "--enabled-only"])
    environment = os.environ.copy()
    environment["COLUMNS"] = "240"
    completed = subprocess.run(
        command, check=False, capture_output=True, text=True, env=environment
    )
    if completed.returncode != 0:
        raise ValueError(
            f"Hermes skill listing failed for {profile}: "
            f"exit={completed.returncode}: {completed.stderr.strip()}"
        )
    return completed.stdout


def _verify_expected_manifest(shared_root: Path, records: list[SkillRecord]) -> None:
    manifest_path = shared_root / ".manifest.json"
    if not manifest_path.is_file():
        raise ValueError(f"missing shared skill build manifest: {manifest_path}")
    try:
        manifest = json.loads(manifest_path.read_text())
        expected_records = manifest["skills"]
    except (json.JSONDecodeError, KeyError, TypeError) as error:
        raise ValueError(
            f"invalid shared skill build manifest: {manifest_path}"
        ) from error
    fields = ("group", "name", "sha256", "package_sha256")
    expected = sorted(
        tuple(item[field] for field in fields) for item in expected_records
    )
    actual = sorted(
        tuple(getattr(record, field) for field in fields) for record in records
    )
    if actual != expected:
        raise ValueError(
            f"runtime shared skill hashes do not match build manifest: {manifest_path}"
        )


def _listed_skill_names(output: str) -> set[str]:
    """Parse exact skill names from the first column of Hermes' table output."""
    ansi_escape = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
    names: set[str] = set()
    for raw_line in output.splitlines():
        line = ansi_escape.sub("", raw_line).strip()
        if not (line.startswith("│") and line.endswith("│")):
            continue
        cells = [cell.strip() for cell in line.strip("│").split("│")]
        if len(cells) < 2 or not NAME_PATTERN.fullmatch(cells[0]):
            continue
        names.add(cells[0])
    return names


def _active_local_skill_names(home: Path, profile: str) -> set[str]:
    profile_home = (
        home / ".hermes"
        if profile == "default"
        else home / ".hermes/profiles" / profile
    )
    skills_root = profile_home / "skills"
    names: set[str] = set()
    if not skills_root.is_dir():
        return names
    for skill_file in skills_root.rglob("SKILL.md"):
        relative = skill_file.relative_to(skills_root)
        if any(part.startswith(".") for part in relative.parts):
            continue
        try:
            frontmatter = _frontmatter(skill_file)
        except (OSError, ValueError):
            continue
        name = frontmatter.get("name")
        if isinstance(name, str):
            names.add(name)
    return names


def check_live(
    home: Path,
    shared_root: Path,
    profile_groups: dict[str, tuple[str, ...]] = PROFILE_GROUPS,
    cli_runner: Callable[[str], str] = _default_cli_runner,
) -> dict:
    home = _logical_absolute(home)
    shared_root = _logical_absolute(shared_root)
    records = validate_source(
        shared_root, profile_groups, allow_build_manifest=True
    )
    _verify_expected_manifest(shared_root, records)
    _check_profile_matrix(home, profile_groups, require_complete=True)
    if os.access(shared_root, os.W_OK):
        raise ValueError(
            f"shared skill root must be read-only for consumers: {shared_root}"
        )

    names_by_group: dict[str, set[str]] = {group: set() for group in SHARED_GROUPS}
    for record in records:
        names_by_group[record.group].add(record.name)
    all_shared_names = {record.name for record in records}
    managed = _managed_paths(shared_root)

    report: dict = {
        "shared_root": str(shared_root),
        "skills": [asdict(record) for record in records],
        "profiles": {},
    }
    for profile, groups in profile_groups.items():
        path = profile_config_path(home, profile)
        config = _load_config(path)
        skills_config = config.get("skills", {})
        if not isinstance(skills_config, dict):
            raise ValueError(f"skills config is not a mapping: {path}")
        external_dirs = skills_config.get("external_dirs", [])
        if not isinstance(external_dirs, list):
            raise ValueError(f"skills.external_dirs is not a list: {path}")
        actual_managed = [item for item in external_dirs if item in managed]
        expected_dirs = _expected_external_dirs(shared_root, groups)
        if actual_managed != expected_dirs:
            raise ValueError(
                f"shared skill config mismatch for {profile}: "
                f"expected={expected_dirs}, actual={actual_managed}"
            )

        expected_names = set().union(*(names_by_group[group] for group in groups))
        local_names = _active_local_skill_names(home, profile)
        local_collisions = sorted(expected_names & local_names)
        if local_collisions:
            raise ValueError(
                f"local/shared skill name collision for {profile}: {local_collisions}"
            )
        listed_names = _listed_skill_names(cli_runner(profile))
        missing_names = sorted(expected_names - listed_names)
        unexpected_names = sorted(
            ((all_shared_names - expected_names) & listed_names) - local_names
        )
        if missing_names:
            raise ValueError(f"missing shared skill for {profile}: {missing_names}")
        if unexpected_names:
            raise ValueError(
                f"unexpected shared skill for {profile}: {unexpected_names}"
            )
        report["profiles"][profile] = {
            "groups": list(groups),
            "skills": sorted(expected_names),
            "config": str(path),
        }
    return report


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("configure", "check-source", "check-live"))
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument(
        "--shared-root",
        type=Path,
        default=Path.home() / ".local/share/hermes/shared-skills",
    )
    return parser


def main(argv: list[str]) -> int:
    arguments = _parser().parse_args(argv[1:])
    try:
        if arguments.command == "configure":
            apply(arguments.home, arguments.shared_root)
            result = {"configured_profiles": sorted(PROFILE_GROUPS)}
        elif arguments.command == "check-source":
            result = {
                "skills": [
                    asdict(record) for record in validate_source(arguments.shared_root)
                ]
            }
        else:
            result = check_live(arguments.home, arguments.shared_root)
    except (OSError, ValueError) as error:
        print(f"shared skill validation failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
