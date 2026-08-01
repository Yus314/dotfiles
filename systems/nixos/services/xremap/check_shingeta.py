#!/usr/bin/env python3
"""Validate bidirectional invariants in the Shingeta xremap table."""

from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path
from typing import Any

from ruamel.yaml import YAML  # type: ignore[import-not-found]

EXPECTED_PRIMARY_KEYS = 32
EXPECTED_DIRECTED_CHORDS = 204
EXPECTED_UNORDERED_CHORDS = 102


def event_sequence(value: Any) -> tuple[str, ...]:
    """Normalize one xremap output into its delivered event sequence."""
    if isinstance(value, str):
        return (value,)
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return tuple(value)
    raise ValueError(f"unsupported xremap output: {value!r}")


def load_shingeta(path: Path) -> dict[str, Any]:
    yaml = YAML(typ="safe")
    yaml.version = (1, 2)
    document = yaml.load(path)
    for keymap in document.get("keymap", []):
        if keymap.get("name") == "shinyou":
            return keymap["remap"]
    raise ValueError("named Shingeta keymap 'shinyou' was not found")


def validate(path: Path) -> None:
    remap = load_shingeta(path)
    directed: dict[tuple[str, str], tuple[str, ...]] = {}
    singles: dict[str, tuple[str, ...]] = {}

    for primary, rule in remap.items():
        if not isinstance(rule, dict):
            raise ValueError(f"rule for {primary!r} is not a mapping")
        singles[str(primary)] = event_sequence(rule["timeout_key"])
        for secondary, output in rule.get("remap", {}).items():
            directed[(str(primary), str(secondary))] = event_sequence(output)

    unordered: dict[tuple[str, str], list[tuple[str, str]]] = defaultdict(list)
    for primary, secondary in directed:
        ordered = sorted((primary, secondary))
        unordered[(ordered[0], ordered[1])].append((primary, secondary))

    errors: list[str] = []
    for (first, second), directions in sorted(unordered.items()):
        forward = directed.get((first, second))
        reverse = directed.get((second, first))
        if forward is None or reverse is None:
            errors.append(f"missing reverse rule for {first!r} + {second!r}: {directions!r}")
        elif forward != reverse:
            errors.append(
                f"order-dependent output for {first!r} + {second!r}: "
                f"{forward!r} != {reverse!r}"
            )

    expected_counts = {
        "primary keys": (len(singles), EXPECTED_PRIMARY_KEYS),
        "directed chords": (len(directed), EXPECTED_DIRECTED_CHORDS),
        "unordered chords": (len(unordered), EXPECTED_UNORDERED_CHORDS),
    }
    for label, (actual, expected) in expected_counts.items():
        if actual != expected:
            errors.append(f"unexpected {label}: {actual}, expected {expected}")

    if errors:
        raise SystemExit("Shingeta validation failed:\n- " + "\n- ".join(errors))

    print(
        "Shingeta validation passed: "
        f"{len(singles)} primary keys, {len(directed)} directed chords, "
        f"{len(unordered)} unordered chords, all reverse outputs symmetric"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("config", type=Path)
    args = parser.parse_args()
    validate(args.config)


if __name__ == "__main__":
    main()
