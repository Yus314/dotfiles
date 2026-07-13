#!/usr/bin/env python3
"""Maintain the default profile's cross-profile weekly summary source index.

This is intentionally deterministic/no-agent: it checks whether compact weekly
summary artifacts exist, rewrites ~/org/profile-summaries/YYYY-Www.md as a
source-status index, and prints only when the status changed since the previous
run. It never reads/copies raw domain data and never invents missing summaries.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
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

SOURCES = [
    {
        "domain": "Calendar",
        "profile": "default",
        "path": HOME / "org/calendar.org",
        "exists_text": "Available: local calendar export exists. Check health status before assuming completeness.",
        "missing_text": "Missing: local calendar export is unavailable; do not infer no events.",
    },
    {
        "domain": "Org tasks / diary context",
        "profile": "default",
        "path": HOME / "org",
        "exists_text": "Available: read directly; preserve curated weekly-report structure.",
        "missing_text": "Missing: org directory unavailable.",
    },
    {
        "domain": "Food",
        "profile": "food",
        "path": HOME / "org/food/weekly" / f"{WEEK}.md",
        "exists_text": "Available: use compact food weekly summary; do not read raw meal logs by default.",
        "missing_text": "Missing: do not invent food content.",
    },
    {
        "domain": "Finance",
        "profile": "finance",
        "path": HOME / "ledger/personal/reports/weekly" / f"{WEEK}.md",
        "exists_text": "Available: use compact finance weekly summary; do not copy raw ledger data into default.",
        "missing_text": "Missing: do not copy raw ledger data into default.",
    },
    {
        "domain": "Math",
        "profile": "math",
        "path": HOME / "study_log/reviews/weekly" / f"{WEEK}.md",
        "exists_text": "Available: use compact math progress/confusion/next-step summary.",
        "missing_text": "Missing: ask math profile / study_log when needed; do not invent progress.",
    },
    {
        "domain": "Economics",
        "profile": "economics",
        "path": HOME / "study_log/economics/reviews/weekly" / f"{WEEK}.md",
        "exists_text": "Available: use compact economics progress/confusion/restart summary; keep detailed source/OCR work in economics.",
        "missing_text": "Missing: ask the economics profile to summarize progress; do not infer study progress from source preparation.",
    },
    {
        "domain": "Health",
        "profile": "health",
        "path": HOME / "org/health/google-health/weekly" / f"{WEEK}.md",
        "exists_text": "Available: use compact health weekly summary; avoid raw streams.",
        "missing_text": "Missing: use compact daily/coach summaries only when explicitly needed.",
    },
    {
        "domain": "English learning",
        "profile": "english",
        "path": HOME / "study_log/english/reviews/weekly" / f"{WEEK}.md",
        "exists_text": "Available: use learning progress/error-pattern summary; avoid line-by-line correction history.",
        "missing_text": "Missing: use English profile artifacts, not raw chat history.",
    },
    {
        "domain": "Career",
        "profile": "career",
        "path": HOME / "career/reviews/weekly" / f"{WEEK}.md",
        "exists_text": "Available: use compact career weekly summary.",
        "missing_text": "Missing: no standard career weekly artifact has been produced yet.",
    },
    {
        "domain": "Indie dev",
        "profile": "indiedev",
        "path": HOME / "indiedev/reviews/weekly" / f"{WEEK}.md",
        "exists_text": "Available: use compact indie-dev weekly summary.",
        "missing_text": "Missing: profile exists but is not yet in the regular summary loop.",
    },
]


def atomic_write(path: Path, content: str, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", text=True)
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


def status_for(src: dict) -> dict:
    p = src["path"]
    exists = p.exists()
    size = p.stat().st_size if exists and p.is_file() else None
    if exists:
        status = src["exists_text"]
        if size == 0:
            status = "Present but empty: treat as not yet summarized."
    else:
        status = src["missing_text"]
    return {
        "domain": src["domain"],
        "profile": src["profile"],
        "path": rel(p),
        "exists": exists,
        "size": size,
        "status": status,
    }


def render(rows: list[dict]) -> str:
    lines = [
        f"# Profile summary index — {WEEK}",
        "",
        "Status: source-status index, not a curated weekly report",
        "Owner profile: `default`",
        f"Generated: {GENERATED}",
        "",
        "This file tracks whether each profile-separated domain has produced a compact weekly summary for the current ISO week. Missing files are treated as ‘not summarized yet,’ not as evidence that nothing happened.",
        "",
        "## Source status",
        "",
        "| Domain | Owner profile | Expected source | Status |",
        "|---|---|---|---|",
    ]
    for r in rows:
        lines.append(f"| {r['domain']} | {r['profile']} | `{r['path']}` | {r['status']} |")
    lines += [
        "",
        "## Default integration rule",
        "",
        "- Use this as a source-health index only.",
        "- If a source is missing, report that briefly and continue with available sources.",
        "- Do not rewrite `~/weekly-report` unless explicitly asked.",
        "- Do not merge domain raw data into default profile memory.",
        "- Carry-forward candidates should stay short and go under `来週のこと` when drafting for the weekly report.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    rows = [status_for(s) for s in SOURCES]
    content = render(rows)
    atomic_write(INDEX_PATH, content)

    digest_payload = json.dumps(
        [{k: r[k] for k in ("domain", "path", "exists", "size")} for r in rows],
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
        json.dumps({"week": WEEK, "date": GENERATED, "digest": digest, "rows": rows}, ensure_ascii=False, indent=2),
    )

    if old != digest:
        missing = [r for r in rows if not r["exists"] or r["size"] == 0]
        available = [r for r in rows if r["exists"] and r["size"] != 0]
        print(f"Profile summary source status changed for {WEEK}.")
        print(f"Index: {rel(INDEX_PATH)}")
        print(f"Available summaries/files: {len(available)}/{len(rows)}")
        if missing:
            print("Missing/not-ready compact summaries:")
            for r in missing:
                print(f"- {r['domain']} ({r['profile']}): {r['path']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
