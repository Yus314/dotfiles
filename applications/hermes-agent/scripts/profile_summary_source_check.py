#!/usr/bin/env python3
"""Maintain the default profile's cross-profile weekly summary source index.

This deterministic/no-agent checker distinguishes file presence from semantic
readiness. A bootstrap/source-health file is never reported as a domain-owned
summary. It never copies raw domain data and prints only when status changes.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import re
import tempfile
from pathlib import Path

HOME = Path.home()
TODAY = dt.date.today()
ISO = TODAY.isocalendar()
WEEK = f"{ISO.year}-W{ISO.week:02d}"
GENERATED = TODAY.isoformat()
STATE_DIR = HOME / ".local/state/hermes/profile-summary-source-check"
STATE_FILE = STATE_DIR / f"{WEEK}.json"
INDEX_PATH = HOME / "org/profile-summaries" / f"{WEEK}.md"
BOOTSTRAP_MARKER = "<!-- hermes-bootstrap-weekly-summary -->"
WEEK_PATTERN = re.compile(r"\b20\d{2}-W\d{2}\b")

SOURCES = [
    {
        "kind": "source",
        "domain": "Calendar",
        "profile": "default",
        "path": HOME / "org/calendar.org",
        "exists_text": "Source present: local calendar export exists; check its dedicated health status before assuming completeness.",
        "missing_text": "Missing: local calendar export is unavailable; do not infer no events.",
    },
    {
        "kind": "source",
        "domain": "Org tasks / diary context",
        "profile": "default",
        "path": HOME / "org",
        "exists_text": "Source present: read selectively; preserve curated weekly-report structure.",
        "missing_text": "Missing: org directory unavailable.",
    },
    {
        "kind": "summary",
        "domain": "Food",
        "profile": "food",
        "path": HOME / "org/food/weekly" / f"{WEEK}.md",
    },
    {
        "kind": "summary",
        "domain": "Finance",
        "profile": "finance",
        "path": HOME / "ledger/personal/reports/weekly" / f"{WEEK}.md",
    },
    {
        "kind": "summary",
        "domain": "Math",
        "profile": "math",
        "path": HOME / "study_log/reviews/weekly" / f"{WEEK}.md",
    },
    {
        "kind": "summary",
        "domain": "Economics",
        "profile": "economics",
        "path": HOME / "study_log/economics/reviews/weekly" / f"{WEEK}.md",
    },
    {
        "kind": "summary",
        "domain": "Health",
        "profile": "health",
        "path": HOME / "org/health/google-health/weekly" / f"{WEEK}.md",
    },
    {
        "kind": "summary",
        "domain": "English learning",
        "profile": "english",
        "path": HOME / "study_log/english/reviews/weekly" / f"{WEEK}.md",
    },
    {
        "kind": "summary",
        "domain": "Career",
        "profile": "career",
        "path": HOME / "career/reviews/weekly" / f"{WEEK}.md",
    },
    {
        "kind": "summary",
        "domain": "Indie dev",
        "profile": "indiedev",
        "path": HOME / "indiedev/reviews/weekly" / f"{WEEK}.md",
    },
]


def atomic_write(path: Path, content: str, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", text=True
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary_path, mode)
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def rel(path: Path) -> str:
    try:
        return "~/" + str(path.relative_to(HOME))
    except ValueError:
        return str(path)


def _clean_value(value: str) -> str:
    return value.strip().strip("`\"'")


def _frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---\n"):
        return {}
    parts = text.split("---", 2)
    if len(parts) != 3:
        return {}
    result: dict[str, str] = {}
    for raw in parts[1].splitlines():
        if not raw.strip() or raw.lstrip().startswith("#") or ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        result[key.strip().lower()] = _clean_value(value)
    return result


def _legacy_field(text: str, label: str) -> str | None:
    match = re.search(rf"(?im)^{re.escape(label)}:\s*(.+?)\s*$", text)
    return _clean_value(match.group(1)) if match else None


def _declared_week(text: str, metadata: dict) -> tuple[str | None, str | None]:
    """Return the canonical summary week and an optional validation error.

    Only structured metadata or a Markdown heading may declare the week. Week
    strings in prose are deliberately ignored so a stale summary cannot become
    ready merely by mentioning the current week in its body.
    """
    candidates: list[str] = []
    raw_metadata_week = metadata.get("week")
    if raw_metadata_week is not None:
        metadata_weeks = WEEK_PATTERN.findall(str(raw_metadata_week))
        if len(metadata_weeks) != 1:
            return None, "invalid frontmatter week"
        candidates.append(metadata_weeks[0])
    legacy_week = _legacy_field(text, "Week")
    if legacy_week:
        legacy_weeks = WEEK_PATTERN.findall(legacy_week)
        if len(legacy_weeks) != 1:
            return None, "invalid legacy week"
        candidates.append(legacy_weeks[0])
    for line in text.splitlines():
        if not re.match(r"^#{1,6}\s+", line):
            continue
        heading_weeks = WEEK_PATTERN.findall(line)
        if len(heading_weeks) > 1:
            return None, "multiple weeks in summary heading"
        if heading_weeks:
            candidates.append(heading_weeks[0])
            break
    unique = set(candidates)
    if len(unique) > 1:
        return None, "conflicting declared weeks"
    return (next(iter(unique)) if unique else None), None


def classify_summary(
    path: Path, *, expected_profile: str, expected_week: str
) -> dict:
    """Classify one compact summary without reading any referenced raw sources."""
    if not path.exists():
        return {
            "exists": False,
            "size": 0,
            "state": "missing",
            "ready": False,
            "status": "Missing: no compact summary has been produced.",
            "reason": "file missing",
            "sha256": "",
            "schema_version": "",
        }
    if not path.is_file():
        return {
            "exists": True,
            "size": None,
            "state": "invalid",
            "ready": False,
            "status": "Invalid: expected a summary file but found another path type.",
            "reason": "not a regular file",
            "sha256": "",
            "schema_version": "",
        }

    content = path.read_bytes()
    size = len(content)
    digest = hashlib.sha256(content).hexdigest()
    text = content.decode("utf-8", errors="replace")
    metadata = _frontmatter(text)
    schema = metadata.get("schema_version", "")
    status = metadata.get("status") or _legacy_field(text, "Status") or ""
    owner = (
        metadata.get("owner_profile")
        or _legacy_field(text, "Owner profile")
        or ""
    )
    status_lower = status.lower()
    declared_week, week_error = _declared_week(text, metadata)

    base = {
        "exists": True,
        "size": size,
        "sha256": digest,
        "schema_version": schema,
    }
    if size == 0:
        return {
            **base,
            "state": "invalid",
            "ready": False,
            "status": "Invalid: present but empty.",
            "reason": "empty file",
        }
    if BOOTSTRAP_MARKER in text or "bootstrap" in status_lower:
        return {
            **base,
            "state": "bootstrap",
            "ready": False,
            "status": "Bootstrap only: file exists but the owner profile has not attested a weekly handoff.",
            "reason": "bootstrap marker/status",
        }
    if owner and owner != expected_profile:
        return {
            **base,
            "state": "invalid",
            "ready": False,
            "status": f"Invalid: owner `{owner}` does not match expected `{expected_profile}`.",
            "reason": "owner mismatch",
        }
    if week_error:
        return {
            **base,
            "state": "invalid",
            "ready": False,
            "status": f"Invalid: {week_error}.",
            "reason": week_error,
        }
    if declared_week and declared_week != expected_week:
        return {
            **base,
            "state": "stale",
            "ready": False,
            "status": f"Stale: content does not cover `{expected_week}`.",
            "reason": "week mismatch",
        }
    if status_lower in {"degraded", "error"} or status_lower.startswith("degraded"):
        return {
            **base,
            "state": "degraded",
            "ready": False,
            "status": "Degraded: owner reported a source or generation problem.",
            "reason": status or "degraded",
        }
    if "source-status" in status_lower or "health summary" in status_lower:
        return {
            **base,
            "state": "source-health-only",
            "ready": False,
            "status": "Source health only: not a reviewed domain summary.",
            "reason": status,
        }
    if status_lower.startswith("domain-owned"):
        if not owner:
            return {
                **base,
                "state": "invalid",
                "ready": False,
                "status": "Invalid: domain-owned status has no owner profile.",
                "reason": "missing owner",
            }
        if declared_week != expected_week:
            return {
                **base,
                "state": "stale",
                "ready": False,
                "status": f"Stale: domain-owned summary does not identify `{expected_week}`.",
                "reason": "missing current week",
            }
        return {
            **base,
            "state": "domain-owned",
            "ready": True,
            "status": "Ready: owner-attested domain summary.",
            "reason": "owner-attested",
        }
    return {
        **base,
        "state": "needs-owner-review",
        "ready": False,
        "status": "Present but not ready: owner profile review/attestation is required.",
        "reason": status or "missing recognized status",
    }


def status_for(src: dict) -> dict:
    path = src["path"]
    if src.get("kind") == "summary":
        result = classify_summary(
            path,
            expected_profile=src["profile"],
            expected_week=WEEK,
        )
    else:
        exists = path.exists()
        size = path.stat().st_size if exists and path.is_file() else None
        state = "source-present" if exists else "missing"
        result = {
            "exists": exists,
            "size": size,
            "state": state,
            "ready": exists,
            "status": src["exists_text"] if exists else src["missing_text"],
            "reason": state,
            "sha256": "",
            "schema_version": "",
        }
    return {
        "domain": src["domain"],
        "profile": src["profile"],
        "path": rel(path),
        **result,
    }


def render(rows: list[dict]) -> str:
    summary_rows = [row for row in rows if row["profile"] != "default"]
    ready_count = sum(row["state"] == "domain-owned" for row in summary_rows)
    not_ready_count = len(summary_rows) - ready_count
    lines = [
        f"# Profile summary index — {WEEK}",
        "",
        "Status: semantic source-status index, not a curated weekly report",
        "Owner profile: `default`",
        f"Generated: {GENERATED}",
        "",
        "File presence is not treated as summary readiness. Bootstrap, stale, degraded, and unreviewed files remain not ready.",
        "",
        "## Readiness summary",
        "",
        f"- domain-owned: {ready_count}",
        f"- not ready: {not_ready_count}",
        "",
        "## Source status",
        "",
        "| Domain | Owner profile | Expected source | State | Status |",
        "|---|---|---|---|---|",
    ]
    for row in rows:
        lines.append(
            f"| {row['domain']} | {row['profile']} | `{row['path']}` | "
            f"`{row['state']}` | {row['status']} |"
        )
    lines += [
        "",
        "## Default integration rule",
        "",
        "- Treat only `domain-owned` summaries as reviewed domain signals.",
        "- Bootstrap/missing/stale/degraded means ‘not summarized or not ready,’ never ‘nothing happened.’",
        "- Do not inspect domain raw data to compensate for a missing handoff.",
        "- Do not rewrite `~/weekly-report` unless explicitly asked.",
        "- Do not merge domain raw data into default profile memory.",
        "- Nightly review may surface at most two deadline/blocker/degraded signals; weekly review handles broader integration.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    rows = [status_for(source) for source in SOURCES]
    content = render(rows)
    atomic_write(INDEX_PATH, content)

    digest_payload = json.dumps(
        [
            {
                key: row[key]
                for key in (
                    "domain",
                    "path",
                    "exists",
                    "size",
                    "state",
                    "ready",
                    "sha256",
                )
            }
            for row in rows
        ],
        sort_keys=True,
        ensure_ascii=False,
    )
    digest = hashlib.sha256(digest_payload.encode("utf-8")).hexdigest()
    old = None
    if STATE_FILE.exists():
        try:
            old = json.loads(STATE_FILE.read_text()).get("digest")
        except Exception:
            old = None
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    atomic_write(
        STATE_FILE,
        json.dumps(
            {"week": WEEK, "date": GENERATED, "digest": digest, "rows": rows},
            ensure_ascii=False,
            indent=2,
        ),
    )

    if old != digest:
        domain_rows = [row for row in rows if row["profile"] != "default"]
        ready = [row for row in domain_rows if row["ready"]]
        not_ready = [row for row in domain_rows if not row["ready"]]
        print(f"Profile summary readiness changed for {WEEK}.")
        print(f"Index: {rel(INDEX_PATH)}")
        print(f"Domain-owned summaries: {len(ready)}/{len(domain_rows)}")
        if not_ready:
            print("Not-ready domain handoffs:")
            for row in not_ready:
                print(f"- {row['domain']} ({row['profile']}): {row['state']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
