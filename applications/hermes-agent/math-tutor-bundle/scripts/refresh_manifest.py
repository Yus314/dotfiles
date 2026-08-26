#!/usr/bin/env python3
"""Refresh the deterministic math tutor bundle manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifest.json"
EXCLUDED_PARTS = {"tests", "__pycache__", "candidates"}
EXCLUDED_NAMES = {"manifest.json"}

SKILLS = [
    {
        "name": "math-book-study-workflow",
        "source": "skills/math-book-study-workflow",
        "rationale": "Core proof-book registration, Socratic hint ladder, and small durable learning-delta logs.",
    },
    {
        "name": "grounded-math-document-study",
        "source": "skills/grounded-math-document-study",
        "rationale": "Exact PDF/source identity, formula/page evidence, and abstention for source-grounded mathematics.",
    },
    {
        "name": "cross-machine-study-environments",
        "source": "skills/cross-machine-study-environments",
        "rationale": "Git/one-way-artifact authority and host-local live-state rules needed for Lawliet/Watari handoff.",
    },
]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def payload_files() -> list[Path]:
    result = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(ROOT)
        if path.name in EXCLUDED_NAMES or any(part in EXCLUDED_PARTS for part in rel.parts):
            continue
        result.append(rel)
    return sorted(result, key=lambda item: item.as_posix())


def build_manifest() -> dict:
    digests = {
        rel.as_posix(): sha256_bytes((ROOT / rel).read_bytes())
        for rel in payload_files()
    }
    identity = {
        "schema_version": 1,
        "bundle_version": "1.0.0-candidate.1",
        "honcho": {
            "workspace": "hermes-math",
            "user_peer": "kaki-math",
            "ai_peers": ["math-lawliet", "math-watari"],
        },
        "expected_model": {"provider": "openai-codex", "model": "gpt-5.6-sol"},
        "skill_allowlist": SKILLS,
        "content_digests": digests,
    }
    aggregate_input = json.dumps(identity, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return {**identity, "aggregate_sha256": sha256_bytes(aggregate_input)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="replace manifest.json")
    args = parser.parse_args()
    manifest = build_manifest()
    text = json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if args.write:
        MANIFEST.write_text(text, encoding="utf-8")
        print(f"wrote {MANIFEST} aggregate={manifest['aggregate_sha256']}")
        return 0
    if not MANIFEST.exists() or MANIFEST.read_text(encoding="utf-8") != text:
        print("manifest drift: run refresh_manifest.py --write")
        return 1
    print(f"manifest ok aggregate={manifest['aggregate_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
