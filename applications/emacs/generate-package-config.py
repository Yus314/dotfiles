#!/usr/bin/env python3
"""Regenerate evaluation-time Emacs Org inputs used for package discovery."""

from __future__ import annotations

import argparse
from pathlib import Path

APPLICATIONS = ("emacs", "emacs-minimal")


def combined_org(app_dir: Path) -> str:
    parts = [(app_dir / "elisp" / "init.org").read_text(encoding="utf-8")]
    parts.extend(
        path.read_text(encoding="utf-8")
        for path in sorted((app_dir / "elisp" / "modules").glob("*.org"))
    )
    return "\n".join(parts)


def generate_configs(
    applications_dir: Path,
    selected: tuple[str, ...] | None,
    check: bool,
) -> list[Path]:
    """Generate or check configs for SELECTED applications and return stale paths."""
    names = APPLICATIONS if selected is None else selected
    unknown = [name for name in names if name not in APPLICATIONS]
    if unknown:
        raise ValueError(f"unknown application: {', '.join(unknown)}")

    stale: list[Path] = []
    for name in names:
        app_dir = applications_dir / name
        target = app_dir / "emacspkg" / "emacs-config.org"
        expected = combined_org(app_dir)
        current = target.read_text(encoding="utf-8") if target.is_file() else None
        if current == expected:
            continue
        stale.append(target)
        if not check:
            target.write_text(expected, encoding="utf-8")
    return stale


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail instead of writing when generated files are stale",
    )
    parser.add_argument(
        "--application",
        action="append",
        choices=APPLICATIONS,
        dest="applications",
        help="limit generation/checking to one application; repeatable",
    )
    args = parser.parse_args()
    applications_dir = Path(__file__).resolve().parent.parent
    selected = tuple(args.applications) if args.applications else None
    stale = generate_configs(applications_dir, selected, args.check)

    if args.check and stale:
        for path in stale:
            print(f"stale generated Emacs package config: {path}")
        command = "applications/emacs/generate-package-config.py"
        if selected:
            command += " " + " ".join(
                f"--application {name}" for name in selected
            )
        print(f"run {command}")
        return 1
    if not args.check:
        print(f"updated={len(stale)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
