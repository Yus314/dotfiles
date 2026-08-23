#!/usr/bin/env python3
"""Fail-closed consumer gate for cross-profile handoff Markdown files."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path
from typing import Any

import yaml

from profile_exchange_schema import RETENTION_CLASSES, validate_handoff


MAX_HANDOFF_BYTES = 1024 * 1024


class HandoffCheckError(RuntimeError):
    """An expected fail-closed validation or policy loading error."""


def _load_registry_policy(
    registry_path: Path, *, target: str
) -> tuple[set[str], set[str], set[str]]:
    try:
        registry = json.loads(registry_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise HandoffCheckError("registry_unavailable") from error
    if not isinstance(registry, dict) or registry.get("schema_version") != 2:
        raise HandoffCheckError("registry_schema_invalid")
    profiles = registry.get("profiles")
    if not isinstance(profiles, dict) or target not in profiles:
        raise HandoffCheckError("target_profile_unknown")
    exchange = registry.get("information_exchange")
    handoff = exchange.get("handoff") if isinstance(exchange, dict) else None
    if not isinstance(handoff, dict):
        raise HandoffCheckError("handoff_policy_missing")
    if (
        handoff.get("schema_family") != "cross_profile_handoff"
        or handoff.get("schema_version") != 2
    ):
        raise HandoffCheckError("handoff_policy_schema_invalid")

    purposes = handoff.get("allowed_purposes")
    if (
        not isinstance(purposes, list)
        or not purposes
        or any(not isinstance(item, str) or not item.strip() for item in purposes)
    ):
        raise HandoffCheckError("handoff_purposes_invalid")
    retention = handoff.get("retention_classes")
    if not isinstance(retention, list) or set(retention) != RETENTION_CLASSES:
        raise HandoffCheckError("handoff_retention_classes_invalid")
    matrix = handoff.get("destination_sensitivity")
    allowed = matrix.get(target) if isinstance(matrix, dict) else None
    if (
        not isinstance(allowed, list)
        or not allowed
        or any(not isinstance(item, str) or not item.strip() for item in allowed)
    ):
        raise HandoffCheckError("destination_sensitivity_missing")
    return set(profiles), set(purposes), set(allowed)


def _load_seen_ids(path: Path | None) -> set[str]:
    if path is None:
        return set()
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise HandoffCheckError("seen_ids_unavailable") from error
    if isinstance(payload, dict):
        payload = payload.get("consumed_ids")
    if not isinstance(payload, list) or any(not isinstance(item, str) for item in payload):
        raise HandoffCheckError("seen_ids_invalid")
    return set(payload)


def _load_frontmatter(path: Path) -> dict[str, Any]:
    try:
        stat = path.stat()
    except OSError as error:
        raise HandoffCheckError("artifact_unavailable") from error
    if not path.is_file():
        raise HandoffCheckError("artifact_not_regular_file")
    if stat.st_size > MAX_HANDOFF_BYTES:
        raise HandoffCheckError("artifact_too_large")
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise HandoffCheckError("artifact_unreadable") from error
    if not text.startswith("---\n"):
        raise HandoffCheckError("frontmatter_missing")
    closing = text.find("\n---\n", 4)
    if closing < 0:
        raise HandoffCheckError("frontmatter_unterminated")
    try:
        metadata = yaml.safe_load(text[4:closing])
    except yaml.YAMLError as error:
        raise HandoffCheckError("frontmatter_invalid") from error
    if not isinstance(metadata, dict) or any(not isinstance(key, str) for key in metadata):
        raise HandoffCheckError("frontmatter_not_mapping")
    return metadata


def check_handoff(
    path: Path,
    *,
    target: str,
    registry_path: Path,
    now: dt.datetime,
    seen_ids_path: Path | None = None,
) -> dict[str, Any]:
    """Validate metadata and return a compact result that never echoes the body."""
    try:
        registered, purposes, sensitivity = _load_registry_policy(
            registry_path, target=target
        )
        seen_ids = _load_seen_ids(seen_ids_path)
        metadata = _load_frontmatter(path)
    except HandoffCheckError as error:
        return {"valid": False, "reason_codes": [str(error)]}

    errors = validate_handoff(
        metadata,
        expected_target=target,
        now=now,
        registered_profiles=registered,
        allowed_purposes=purposes,
        allowed_sensitivity=sensitivity,
        seen_ids=seen_ids,
    )
    if errors:
        return {"valid": False, "reason_codes": errors}
    return {
        "valid": True,
        "path": str(path),
        "handoff_id": metadata["handoff_id"],
        "source_profile": metadata["source_profile"],
        "target_profiles": metadata["target_profiles"],
        "purpose": metadata["purpose"],
        "valid_until": (
            metadata["valid_until"].isoformat()
            if isinstance(metadata["valid_until"], dt.datetime)
            else metadata["valid_until"]
        ),
        "sensitivity": metadata["sensitivity"],
        "retention_class": metadata["retention_class"],
        "source_health": metadata["source_health"],
        "reason_codes": [],
    }


def _aware_datetime(value: str) -> dt.datetime:
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be an ISO-8601 datetime") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise argparse.ArgumentTypeError("must include a timezone")
    return parsed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("--target", required=True)
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--now", type=_aware_datetime)
    parser.add_argument("--seen-ids", type=Path)
    args = parser.parse_args(argv)
    now = args.now or dt.datetime.now(dt.timezone.utc)
    result = check_handoff(
        args.path,
        target=args.target,
        registry_path=args.registry,
        now=now,
        seen_ids_path=args.seen_ids,
    )
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0 if result["valid"] else 1


if __name__ == "__main__":
    sys.exit(main())
