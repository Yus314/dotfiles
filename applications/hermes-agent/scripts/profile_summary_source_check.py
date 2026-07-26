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
REGISTRY_PATH = HOME / ".local/share/hermes/profile-registry.json"
BOOTSTRAP_MARKER = "<!-- hermes-bootstrap-weekly-summary -->"
WEEK_PATTERN = re.compile(r"\b20\d{2}-W\d{2}\b")
SUMMARY_POLICIES = {
    "none",
    "active-weekly",
    "on-demand",
    "source-health-only",
    "blocked",
}


class SummaryPolicyError(RuntimeError):
    """Raised when the fail-closed integration policy cannot be loaded."""


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
        "path": HOME / ".local/state/hermes/study-handoffs/math" / f"{WEEK}.md",
    },
    {
        "kind": "summary",
        "domain": "Economics",
        "profile": "economics",
        "path": HOME / ".local/state/hermes/study-handoffs/economics" / f"{WEEK}.md",
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
        "path": HOME / ".local/state/hermes/study-handoffs/english" / f"{WEEK}.md",
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


def load_summary_policies(path: Path) -> dict[str, dict[str, str]]:
    """Load validated policy or fail closed rather than disabling monitoring."""
    try:
        registry = json.loads(path.read_text())
    except (OSError, AttributeError, UnicodeError, json.JSONDecodeError) as error:
        raise SummaryPolicyError("summary policy registry is unavailable or invalid") from error
    if not isinstance(registry, dict) or registry.get("schema_version") != 2:
        raise SummaryPolicyError("summary policy registry schema is not version 2")
    profiles = registry.get("profiles")
    if not isinstance(profiles, dict):
        raise SummaryPolicyError("summary policy registry has no profiles object")
    result: dict[str, dict[str, str]] = {}
    for profile, spec in profiles.items():
        if not isinstance(profile, str) or not isinstance(spec, dict):
            raise SummaryPolicyError("summary policy registry has an invalid profile entry")
        policy = spec.get("summary_policy")
        reason = spec.get("summary_policy_reason", "")
        summary_path = spec.get("summary_path")
        if policy not in SUMMARY_POLICIES or not isinstance(reason, str):
            raise SummaryPolicyError(f"invalid summary policy for profile {profile}")
        if policy == "blocked" and not reason.strip():
            raise SummaryPolicyError(f"blocked profile {profile} has no reason")
        if policy == "none" and summary_path is not None:
            raise SummaryPolicyError(
                f"profile {profile} with no summary policy has a summary path"
            )
        if policy != "none" and (
            not isinstance(summary_path, str) or summary_path.count("{week}") != 1
        ):
            raise SummaryPolicyError(f"invalid summary path for profile {profile}")
        result[profile] = {
            "summary_policy": policy,
            "summary_policy_reason": reason,
            "summary_path": summary_path or "",
        }
    return result


def apply_summary_policies(
    rows: list[dict], policies: dict[str, dict[str, str]]
) -> list[dict]:
    annotated = []
    for row in rows:
        if row["profile"] == "default":
            policy = {"summary_policy": "source", "summary_policy_reason": ""}
        else:
            try:
                policy = policies[row["profile"]]
            except KeyError as error:
                raise SummaryPolicyError(
                    f"summary policy missing for profile {row['profile']}"
                ) from error
            expected_path = policy["summary_path"].replace("{week}", WEEK)
            if expected_path != row["path"]:
                raise SummaryPolicyError(
                    f"summary path drift for profile {row['profile']}: "
                    f"registry={expected_path} checker={row['path']}"
                )
        annotated_row = {**row, **policy}
        if policy["summary_policy"] == "blocked":
            annotated_row.update(
                observed_state=row["state"],
                observed_ready=row["ready"],
                state="blocked",
                ready=False,
                status=f"Blocked by integration policy: {policy['summary_policy_reason']}.",
                reason=policy["summary_policy_reason"],
            )
        elif policy["summary_policy"] == "source-health-only" and row["ready"]:
            annotated_row.update(
                observed_state=row["state"],
                observed_ready=row["ready"],
                state="policy-excluded",
                ready=False,
                status="Policy-excluded: owner content is not exposed as an integrable domain summary.",
                reason="source-health-only policy",
            )
        annotated.append(annotated_row)
    return annotated


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
    weekly_rows = [
        row for row in summary_rows if row.get("summary_policy") == "active-weekly"
    ]
    weekly_ready = sum(row["state"] == "domain-owned" for row in weekly_rows)
    blocked_rows = [
        row for row in summary_rows if row.get("summary_policy") == "blocked"
    ]
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
        f"- weekly-required: {weekly_ready}/{len(weekly_rows)}",
        f"- blocked: {len(blocked_rows)}",
        f"- domain-owned across all policies: {ready_count}",
        f"- not ready across all policies: {not_ready_count}",
        "",
        "## Source status",
        "",
        "| Domain | Owner profile | Policy | Expected source | State | Status |",
        "|---|---|---|---|---|---|",
    ]
    for row in rows:
        policy = row.get(
            "summary_policy", "source" if row["profile"] == "default" else "on-demand"
        )
        policy_reason = row.get("summary_policy_reason", "")
        status = row["status"]
        if policy_reason and policy_reason not in status:
            status = f"{status} Policy note: {policy_reason}."
        lines.append(
            f"| {row['domain']} | {row['profile']} | `{policy}` | `{row['path']}` | "
            f"`{row['state']}` | {status} |"
        )
    lines += [
        "",
        "## Default integration rule",
        "",
        "- Automatically integrate only `active-weekly` rows whose state is `domain-owned`.",
        "- Use `on-demand` domain-owned summaries only for an explicit current request.",
        "- Never consume `source-health-only`, `blocked`, `bootstrap`, `missing`, `stale`, `degraded`, or `policy-excluded` rows as domain content.",
        "- Do not inspect domain raw data to compensate for a missing handoff.",
        "- Do not rewrite `~/weekly-report` unless explicitly asked.",
        "- Do not merge domain raw data into default profile memory.",
        "- Nightly review may surface at most two deadline/blocker/degraded signals; weekly review handles broader integration.",
        "",
    ]
    return "\n".join(lines)


SEMANTIC_KEYS = ("domain", "profile", "state", "ready")


def semantic_snapshot(rows: list[dict]) -> list[dict]:
    """Return only state that should be allowed to trigger a user notification.

    File size, mtime-equivalent churn, and content hashes remain useful diagnostic
    state, but they do not mean readiness changed. In particular, a calendar sync
    or an edit to an already-ready handoff must not re-alert the user.
    """
    return [
        {key: row.get(key) for key in SEMANTIC_KEYS}
        for row in sorted(
            rows,
            key=lambda row: (
                str(row.get("profile", "")),
                str(row.get("domain", "")),
            ),
        )
    ]


def _row_key(row: dict) -> tuple[str, str]:
    return (
        str(row.get("profile", "")),
        str(row.get("domain", "")),
    )


def changed_semantic_rows(
    previous_rows: list[dict], rows: list[dict]
) -> list[tuple[dict | None, dict | None]]:
    previous = {_row_key(row): row for row in semantic_snapshot(previous_rows)}
    current = {_row_key(row): row for row in semantic_snapshot(rows)}
    changed: list[tuple[dict | None, dict | None]] = []
    for key in sorted(previous.keys() | current.keys()):
        before = previous.get(key)
        after = current.get(key)
        if before != after:
            changed.append((before, after))
    return changed


def notification_lines(
    previous_rows: list[dict] | None, rows: list[dict]
) -> list[str]:
    """Render a compact semantic delta; the first observation is a silent baseline."""
    if previous_rows is None:
        return []
    changed = changed_semantic_rows(previous_rows, rows)
    current_by_key = {_row_key(row): row for row in rows}
    previous_by_key = {_row_key(row): row for row in previous_rows}
    changed = [
        pair
        for pair in changed
        if (
            (pair[1] or pair[0] or {}).get("profile") == "default"
            or (
                current_by_key.get(
                    _row_key(pair[1] or pair[0] or {}),
                    previous_by_key.get(_row_key(pair[1] or pair[0] or {}), {}),
                ).get("summary_policy")
                == "active-weekly"
            )
        )
    ]
    if not changed:
        return []

    weekly_rows = [
        row
        for row in rows
        if row.get("summary_policy") == "active-weekly"
    ]
    ready_count = sum(row["ready"] for row in weekly_rows)
    lines = [
        f"Semantic readiness changed for {WEEK}.",
        f"Index: {rel(INDEX_PATH)}",
        f"Weekly-required summaries: {ready_count}/{len(weekly_rows)}",
        "Changed signals:",
    ]
    for before, after in changed:
        row = after or before
        assert row is not None
        before_state = before["state"] if before else "absent"
        after_state = after["state"] if after else "absent"
        lines.append(
            f"- {row['domain']} ({row['profile']}): "
            f"{before_state} -> {after_state}"
        )
    return lines


def load_previous_rows(path: Path) -> list[dict] | None:
    """Read a prior state defensively; malformed state becomes a silent baseline."""
    if not path.exists():
        return None
    try:
        stored_rows = json.loads(path.read_text()).get("rows")
    except (OSError, AttributeError, UnicodeError, json.JSONDecodeError):
        return None
    if not isinstance(stored_rows, list) or not all(
        isinstance(row, dict) for row in stored_rows
    ):
        return None
    return stored_rows


def main() -> int:
    policies = load_summary_policies(REGISTRY_PATH)
    rows = apply_summary_policies(
        [status_for(source) for source in SOURCES], policies
    )
    content = render(rows)
    atomic_write(INDEX_PATH, content)

    semantic_payload = json.dumps(
        semantic_snapshot(rows), sort_keys=True, ensure_ascii=False
    )
    digest = hashlib.sha256(semantic_payload.encode("utf-8")).hexdigest()
    previous_rows = load_previous_rows(STATE_FILE)
    lines = notification_lines(previous_rows, rows)
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    atomic_write(
        STATE_FILE,
        json.dumps(
            {"week": WEEK, "date": GENERATED, "digest": digest, "rows": rows},
            ensure_ascii=False,
            indent=2,
        ),
    )

    if lines:
        print("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
