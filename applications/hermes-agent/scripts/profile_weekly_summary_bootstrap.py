#!/usr/bin/env python3
"""Bootstrap compact current-week summaries for profile-separated reviews.

This deterministic/no-agent script creates or refreshes only files marked with
`<!-- hermes-bootstrap-weekly-summary -->`. It does not overwrite human-curated
or domain-generated summaries. It uses file/status inventories and compact
existing review artifacts, not raw finance/food/health/math/economics/English data dumps.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

HOME = Path.home()
TODAY = dt.date.today()
ISO = TODAY.isocalendar()
WEEK = f"{ISO.year}-W{ISO.week:02d}"
WEEK_START = TODAY - dt.timedelta(days=ISO.weekday - 1)
WEEK_END = WEEK_START + dt.timedelta(days=6)
MARKER = "<!-- hermes-bootstrap-weekly-summary -->"
CHANGED: list[Path] = []


def rel(p: Path) -> str:
    try:
        return "~/" + str(p.relative_to(HOME))
    except ValueError:
        return str(p)


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


def write_bootstrap(path: Path, content: str) -> None:
    if path.exists():
        old = path.read_text(encoding="utf-8", errors="replace")
        if MARKER not in old:
            return
        if old == content:
            return
    atomic_write(path, content)
    CHANGED.append(path)


def is_bootstrap_output(p: Path) -> bool:
    # Exclude files produced by this script/checker from inventories so reruns
    # are stable and do not make the script chase its own outputs.
    if p.name == f"{WEEK}.md" and any(part in {"weekly", "profile-summaries"} for part in p.parts):
        return True
    return False


def newest_files(root: Path, patterns: tuple[str, ...], limit: int = 8) -> list[Path]:
    if not root.exists():
        return []
    files: list[Path] = []
    for pat in patterns:
        files.extend([p for p in root.rglob(pat) if p.is_file() and not is_bootstrap_output(p)])
    uniq = sorted(set(files), key=lambda p: p.stat().st_mtime, reverse=True)
    return uniq[:limit]


def files_in_week(root: Path, patterns: tuple[str, ...]) -> list[Path]:
    if not root.exists():
        return []
    out = []
    for pat in patterns:
        for p in root.rglob(pat):
            if not p.is_file() or is_bootstrap_output(p):
                continue
            text_date = re.search(r"20\d{2}-\d{2}-\d{2}", str(p))
            in_week = False
            if text_date:
                try:
                    d = dt.date.fromisoformat(text_date.group(0))
                    in_week = WEEK_START <= d <= WEEK_END
                except ValueError:
                    pass
            if not in_week:
                mdate = dt.date.fromtimestamp(p.stat().st_mtime)
                in_week = WEEK_START <= mdate <= WEEK_END
            if in_week:
                out.append(p)
    return sorted(set(out))


def run(cmd: list[str], cwd: Path | None = None) -> tuple[int, str]:
    try:
        cp = subprocess.run(cmd, cwd=str(cwd) if cwd else None, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        return cp.returncode, cp.stdout.strip()
    except Exception as e:
        return 999, f"{type(e).__name__}: {e}"


def food_summary() -> None:
    root = HOME / "org/food"
    week_files = files_in_week(root / "meals", ("*.md",)) + files_in_week(root / "daily", ("*.md",))
    recent = newest_files(root, ("*.md",), 6)
    content = f"""{MARKER}
# {WEEK} food weekly summary

Status: bootstrap source-status summary
Owner profile: `food`
Generated: {TODAY.isoformat()}

## Source status

- Current-week food meal/daily files found: {len(week_files)}
- Latest known food files: {', '.join(rel(p) for p in recent[:5]) if recent else 'none'}

## Compact summary

No current-week food summary generated from the canonical food DB was found. Treat food as **not reviewed yet** for default weekly review. Do not infer that no meals happened.

## Next action

- [ ] Use the food profile to log/review current meals and regenerate `~/org/food/weekly/{WEEK}.md` from the canonical food data source.

## Privacy / ownership note

This bootstrap file does not copy meal details. If a food-profile generated summary replaces it, that generated summary becomes the source of truth.
"""
    write_bootstrap(root / "weekly" / f"{WEEK}.md", content)


def finance_summary() -> None:
    root = HOME / "ledger/personal"
    ledger = root / "journal.ledger"
    check_rc, check_out = run(["hledger", "-f", str(ledger), "check"]) if ledger.exists() else (1, "journal.ledger missing")
    stats_rc, stats = run(["hledger", "-f", str(ledger), "stats"]) if ledger.exists() else (1, "")
    tx_rc, tx = run(["bash", "-lc", f"hledger -f {str(ledger)!r} print -b {WEEK_START.isoformat()} -e {(WEEK_END + dt.timedelta(days=1)).isoformat()} | awk '/^[0-9]{{4}}-/{{c++}} END{{print c+0}}'"], cwd=root) if ledger.exists() else (1, "0")
    last_txn = "unknown"
    tx_span = "unknown"
    tx_last_7 = "unknown"
    for line in stats.splitlines():
        if line.strip().startswith("Txns span"):
            tx_span = line.split(":",1)[1].strip()
        elif line.strip().startswith("Last txn"):
            last_txn = line.split(":",1)[1].strip()
        elif line.strip().startswith("Txns last 7 days"):
            tx_last_7 = line.split(":",1)[1].strip()
    interpretation = (
        "`hledger check` failed or the ledger is unavailable. Treat finance as **not ready for interpretation** and inspect it in the finance profile."
        if check_rc != 0
        else "Current-week transactions are present. Spending interpretation remains finance-profile work; this bootstrap reports status only."
        if tx_rc == 0 and tx.isdigit() and int(tx) > 0
        else "No current-week transactions were counted. This can mean no activity or stale/incomplete import; do not infer which without a finance-profile review."
    )
    content = f"""{MARKER}
# {WEEK} finance weekly summary

Status: bootstrap read-only health summary
Owner profile: `finance`
Generated: {TODAY.isoformat()}

## Ledger integrity / freshness

- `hledger check`: {'OK' if check_rc == 0 else 'FAILED'}
- Transaction span: {tx_span}
- Last transaction: {last_txn}
- Transactions last 7 days: {tx_last_7}
- Transactions in current ISO week ({WEEK_START.isoformat()}..{WEEK_END.isoformat()}): {tx or '0'}

## Interpretation for default review

{interpretation}

## Next action

- [ ] In the finance profile, run the normal ledger-tools / hledger freshness and import coverage review before drawing spending conclusions.

## Privacy note

This file intentionally contains only health/freshness signals, not transaction details, account balances, or raw ledger rows.
"""
    write_bootstrap(root / "reports/weekly" / f"{WEEK}.md", content)


def math_summary() -> None:
    root = HOME / "study_log"
    sessions_root = root / "sessions"
    books_root = root / "books"
    week_files = files_in_week(sessions_root, ("*.md",))
    recent = newest_files(sessions_root, ("*.md",), 6) + newest_files(books_root, ("*.md",), 4)
    content = f"""{MARKER}
# {WEEK} math weekly summary

Status: bootstrap source-status summary
Owner profile: `math`
Generated: {TODAY.isoformat()}

## Source status

- Current-week math session files found: {len(week_files)}
- Recent math session/book files: {', '.join(rel(p) for p in recent[:6]) if recent else 'none'}

## Compact summary

No math-profile weekly review was found for this week. Treat mathematics as **not reviewed yet** in the default profile. Do not infer progress or blockers from absence of a summary.

## Next session starter

- [ ] Use the math profile to read recent `~/study_log/sessions/` and produce one Socratic next question plus unresolved-confusion list.

## Integration note

Default should consume only compact math summaries and leave deep proof dialogue / structural study_log edits to the math profile.
"""
    write_bootstrap(root / "reviews/weekly" / f"{WEEK}.md", content)


def economics_summary() -> None:
    root = HOME / "study_log/economics"
    active = root / "active.md"
    recent = newest_files(root, ("*.md", "*.json", "*.yaml"), 6)
    content = f"""{MARKER}
# {WEEK} economics weekly summary

Status: bootstrap source-status summary
Owner profile: `economics`
Generated: {TODAY.isoformat()}

## Source status

- Active study state: {rel(active) if active.exists() else 'missing'}
- Recent economics artifacts: {', '.join(rel(p) for p in recent[:5]) if recent else 'none'}

## Compact summary

No economics-profile weekly review was found for this week. Source/PDF/OCR preparation is not evidence of reading or understanding progress, so default must treat economics as **not reviewed yet** rather than inventing progress.

## Next session starter

- [ ] In the economics profile, confirm the actual chapter/section/page, state its central question in one sentence, and record one unresolved concept or next check.

## Integration note

Default should consume only this compact handoff. Keep detailed OCR, page corpus, source-quality experiments, and concept dialogue in the economics profile.
"""
    write_bootstrap(root / "reviews/weekly" / f"{WEEK}.md", content)


def health_summary() -> None:
    root = HOME / "org/health/google-health"
    daily = newest_files(root / "daily", ("*.json",), 8)
    coach = newest_files(root / "coach", ("*.md",), 8)
    ready = files_in_week(root / "state/review-ready", ("*.jsonl",))
    latest_daily = rel(daily[0]) if daily else "none"
    latest_coach = rel(coach[0]) if coach else "none"
    content = f"""{MARKER}
# {WEEK} health weekly summary

Status: bootstrap source-status summary
Owner profile: `health`
Generated: {TODAY.isoformat()}

## Source status

- Latest daily summary: {latest_daily}
- Latest coach summary: {latest_coach}
- Current-week review-ready state files: {len(ready)}

## Compact summary

No current-week compact health summary was found. The paths above report source availability only; verify freshness and pipeline state in the health profile before giving trend advice.

## Next action

- [ ] Use the health profile to verify Google Health data freshness and generate `~/org/health/google-health/weekly/{WEEK}.md` from compact daily/coach summaries if available.

## Privacy note

This bootstrap file does not copy raw health streams or minute-level data.
"""
    write_bootstrap(root / "weekly" / f"{WEEK}.md", content)


def english_summary() -> None:
    root = HOME / "study_log/english"
    lesson_reviews = newest_files(root / "lessons", ("review.md",), 5)
    week_reviews = files_in_week(root / "lessons", ("review.md",))
    lesson_note = "none"
    if lesson_reviews:
        lesson_note = rel(lesson_reviews[0])
    content = f"""{MARKER}
# {WEEK} English learning weekly summary

Status: bootstrap compact learning summary
Owner profile: `english`
Generated: {TODAY.isoformat()}

## Source status

- Current-week lesson review files found: {len(week_reviews)}
- Latest lesson review: {lesson_note}
- TOEIC planning files: `~/study_log/english/toeic/`

## Compact summary

{f'Current-week lesson reviews exist ({len(week_reviews)}). Use the English profile to summarize recurring patterns and the next learning action.' if week_reviews else 'No current-week lesson review was found. Treat English learning as not summarized yet; do not infer inactivity from absence.'}

## Carry-forward candidate

- [ ] In the English profile, turn the latest lesson review into a short weekly plan: next DMM material level, one speaking template, and one TOEIC/technical-English review item.

## Integration note

Do not copy line-by-line corrections into default. Use only compact progress, recurring error patterns, and next learning action.
"""
    write_bootstrap(root / "reviews/weekly" / f"{WEEK}.md", content)


def career_summary() -> None:
    root = HOME / "career"
    content = f"""{MARKER}
# {WEEK} career weekly summary

Status: bootstrap placeholder
Owner profile: `career`
Generated: {TODAY.isoformat()}

## Compact summary

No standard career weekly artifact was found. Treat career as **not reviewed yet** for default weekly review unless the user explicitly asks to inspect career-profile sessions or notes.

## Next action

- [ ] If career review is needed, use the career profile to produce a compact summary of hypotheses, evidence, open questions, and next experiments.
"""
    write_bootstrap(root / "reviews/weekly" / f"{WEEK}.md", content)


def indiedev_summary() -> None:
    root = HOME / "indiedev"
    content = f"""{MARKER}
# {WEEK} indie dev weekly summary

Status: bootstrap placeholder
Owner profile: `indiedev`
Generated: {TODAY.isoformat()}

## Compact summary

The indiedev profile exists, but no regular product-experiment weekly artifact was found. Treat indie dev as **not yet integrated into weekly review** unless explicitly requested.

## Next action

- [ ] If this profile becomes active, create a compact weekly product-experiment packet: target buyer, pain, evidence, MVP/prototype progress, risks, Go/No-Go signal, and next action.
"""
    write_bootstrap(root / "reviews/weekly" / f"{WEEK}.md", content)


def main() -> int:
    food_summary()
    finance_summary()
    math_summary()
    economics_summary()
    health_summary()
    english_summary()
    career_summary()
    indiedev_summary()
    if CHANGED:
        print(f"Bootstrapped/updated {len(CHANGED)} weekly profile summaries for {WEEK}:")
        for p in CHANGED:
            print(f"- {rel(p)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
