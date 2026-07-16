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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail instead of writing when generated files are stale",
    )
    args = parser.parse_args()
    applications_dir = Path(__file__).resolve().parent.parent
    stale: list[Path] = []

    for name in APPLICATIONS:
        app_dir = applications_dir / name
        target = app_dir / "emacspkg" / "emacs-config.org"
        expected = combined_org(app_dir)
        current = target.read_text(encoding="utf-8") if target.is_file() else None
        if current == expected:
            continue
        stale.append(target)
        if not args.check:
            target.write_text(expected, encoding="utf-8")

    if args.check and stale:
        for path in stale:
            print(f"stale generated Emacs package config: {path}")
        print("run applications/emacs/generate-package-config.py")
        return 1
    if not args.check:
        print(f"updated={len(stale)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
