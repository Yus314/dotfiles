#!/usr/bin/env python3
"""Analyze Hermes/Codex usage from the local Hermes SQLite state database.

Produces compact Markdown and CSV reports focused on:
- task groups, with subagent sessions rolled up to their parent task
- heavy/suspicious sessions
- tool output volume
- skill_view output volume

This reads only local Hermes metadata; it is not the official OpenAI/Codex
quota source. Official Codex analytics: https://chatgpt.com/codex/cloud/settings/analytics
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import os
import re
import sqlite3
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Analyze local Hermes/Codex token usage")
    source = p.add_mutually_exclusive_group()
    source.add_argument("--db", default=None, help="Explicit path to Hermes state.db")
    source.add_argument(
        "--profile",
        default=None,
        help="Hermes profile whose state.db should be analyzed (default or a named profile)",
    )
    p.add_argument("--days", type=int, default=7, help="Lookback window in days")
    p.add_argument("--outdir", default=None, help="Output directory; default ~/tmp/hermes-usage/YYYY-MM-DD")
    p.add_argument("--top", type=int, default=20, help="Top rows to show in Markdown tables")
    p.add_argument("--json", action="store_true", help="Also print machine-readable JSON summary to stdout")
    p.add_argument("--summary-template", default="~/.local/share/hermes/shared-skills/usage-ops/hermes-usage-analysis/templates/heavy-task-summary.md", help="Heavy-task working-summary template path")
    p.add_argument("--summary-dir", default="~/tmp/hermes-usage/summary-suggestions", help="Suggested working directory; never treated as curated PIM")
    p.add_argument("--summary-tmp-dir", default=None, help="Suggested working/stub summary directory; default OUTDIR/summary-stubs")
    p.add_argument("--write-summary-stubs", action="store_true", help="Write auto-generated working stubs for queued summary items under --summary-tmp-dir")
    p.add_argument("--make-summary-stub", default="", help="Comma-separated queue_id values to write stubs for, regardless of priority/max count")
    p.add_argument("--summary-stub-priorities", default="high,medium", help="Comma-separated priorities to generate stubs for")
    p.add_argument("--max-summary-stubs", type=int, default=5, help="Maximum number of summary stubs to write when --write-summary-stubs is set")
    p.add_argument("--existing-summary-dirs", default="~/tmp/hermes-usage", help="Comma-separated working directories to scan for existing heavy-task summaries")
    p.add_argument("--large-tool-threshold", type=int, default=50_000, help="Minimum tool output chars to include in large_tool_outputs.csv; set 0 to disable")
    p.add_argument("--large-tool-sample-chars", type=int, default=500, help="Max redacted sample chars for large tool output rows")
    return p.parse_args()


PROFILE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")


def resolve_db_source(
    *, db: str | None, profile: str | None, environ: dict[str, str] | None = None
) -> tuple[str, Path]:
    """Resolve accounting input without silently crossing profile boundaries."""
    env = os.environ if environ is None else environ
    if db and profile:
        raise ValueError("--db and --profile are mutually exclusive")
    if db:
        return "explicit", Path(db).expanduser().resolve()

    selected = (profile or env.get("HERMES_PROFILE") or "default").strip()
    if selected != "default" and not PROFILE_NAME.fullmatch(selected):
        raise ValueError(f"invalid Hermes profile name: {selected!r}")
    root = Path.home() / ".hermes"
    path = (
        root / "state.db"
        if selected == "default"
        else root / "profiles" / selected / "state.db"
    )
    return selected, path.resolve()


def open_db(path: str) -> sqlite3.Connection:
    db = Path(path).expanduser()
    if not db.exists():
        raise SystemExit(f"Hermes state DB not found: {db}")
    con = sqlite3.connect(str(db))
    con.row_factory = sqlite3.Row
    return con


def iso(ts: float | int | None) -> str:
    if not ts:
        return ""
    return dt.datetime.fromtimestamp(float(ts)).isoformat(timespec="seconds")


def day(ts: float | int | None) -> str:
    if not ts:
        return ""
    return dt.datetime.fromtimestamp(float(ts)).strftime("%Y-%m-%d")


def base_title(title: str | None) -> str:
    title = re.sub(r" #\d+$", "", title or "").strip()
    return title or "(untitled)"


def total_tokens(row: sqlite3.Row | dict[str, Any]) -> int:
    return int(row["input_tokens"] or 0) + int(row["output_tokens"] or 0) + int(row["cache_read_tokens"] or 0) + int(row["cache_write_tokens"] or 0)


def write_csv(path: Path, rows: Iterable[dict[str, Any]], fieldnames: list[str]) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in fieldnames})


def md_table(headers: list[str], rows: list[list[Any]]) -> str:
    if not rows:
        return "_No rows._\n"
    out = ["| " + " | ".join(headers) + " |", "|" + "|".join(["---"] * len(headers)) + "|"]
    for row in rows:
        out.append("| " + " | ".join(str(x) for x in row) + " |")
    return "\n".join(out) + "\n"


def fmt_int(n: Any) -> str:
    try:
        return f"{int(n):,}"
    except Exception:
        return str(n)


def fmt_pct(num: float, den: float) -> str:
    if not den:
        return "0.0%"
    return f"{num / den:.1%}"


SECRET_PATTERNS = [
    re.compile(r"(?i)(api[_-]?key|token|secret|password|passwd|authorization|bearer)(\s*[:=]\s*)([^\s'\";,]+)"),
    re.compile(r"(?i)(Authorization:\s*Bearer\s+)([^\s'\";,]+)"),
]


def redact_text(text: str) -> str:
    redacted = text or ""
    for pat in SECRET_PATTERNS:
        if pat.groups >= 3:
            redacted = pat.sub(r"\1\2[REDACTED]", redacted)
        else:
            redacted = pat.sub(r"\1[REDACTED]", redacted)
    return redacted


def compact_sample(text: str, max_chars: int = 500) -> str:
    sample = redact_text(text or "")[:max_chars]
    sample = sample.replace("\r", "\\r").replace("\n", "\\n")
    return re.sub(r"\s+", " ", sample).strip()


def classify_content_kind(tool_name: str, content: str) -> str:
    t = (tool_name or "").lower()
    c = (content or "").lstrip()
    cl = c[:5000].lower()
    if t.startswith("browser_"):
        return "browser-state"
    if t == "skill_view":
        return "skill-doc"
    if t in {"search_files", "web_search", "web_extract", "session_search"}:
        return "search-results"
    if t == "read_file":
        return "file-content"
    if "<!doctype html" in cl or "<html" in cl:
        return "html"
    if c.startswith("{") or c.startswith("["):
        return "json"
    if "traceback (most recent call last)" in cl or re.search(r"\b(exception|error):", cl):
        return "traceback"
    if "diff --git" in cl or "*** begin patch" in cl or "@@" in c[:2000]:
        return "diff/patch"
    if "pytest" in cl or "assertionerror" in cl or " failed" in cl or " collected" in cl:
        return "test-log"
    if "," in c[:500] and "\n" in c[:500]:
        return "csv/table"
    if t == "terminal":
        return "terminal-log"
    return "unknown"


KIND_MITIGATIONS = {
    "html": "Use web_extract/browser targeted extraction; avoid dumping raw HTML.",
    "json": "Use jq/Python to select fields before returning output.",
    "traceback": "Keep full log in a file; return the top frame, failing command, and concise error.",
    "test-log": "Rerun with short traceback or summarize failing tests only.",
    "diff/patch": "Review per file or save the patch to a file; avoid dumping whole diffs.",
    "skill-doc": "Avoid reloading large skills repeatedly; summarize only relevant sections.",
    "search-results": "Narrow queries/results; for file search use count/files_only before targeted reads.",
    "file-content": "Use read_file(offset, limit) narrowly and avoid broad reads.",
    "terminal-log": "Filter with grep/jq/tail or write raw output to a file.",
    "browser-state": "Capture relevant selector/state only, not repeated full snapshots.",
    "csv/table": "Aggregate or sample rows before returning output.",
    "unknown": "Save raw output to a file and return a compact summary.",
}


def mitigation_for(tool_name: str, content_kind: str) -> str:
    return KIND_MITIGATIONS.get(content_kind) or DRIVER_ACTIONS.get(f"{tool_name}-heavy", KIND_MITIGATIONS["unknown"])


def pattern_priority(total_chars: int, count: int, max_chars: int) -> str:
    if total_chars >= 300_000 or count >= 5 or max_chars >= 100_000:
        return "high"
    if total_chars >= 100_000 or count >= 2:
        return "medium"
    return "low"


def build_tool_output_patterns(large_tool_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    groups: dict[tuple[str, str], dict[str, Any]] = {}
    for row in large_tool_rows:
        key = (str(row.get("tool_name") or ""), str(row.get("content_kind") or "unknown"))
        g = groups.setdefault(
            key,
            {
                "tool_name": key[0],
                "content_kind": key[1],
                "count": 0,
                "total_chars": 0,
                "max_chars": 0,
                "total_lines": 0,
                "tasks": set(),
                "example": None,
            },
        )
        chars = int(row.get("output_chars") or 0)
        g["count"] += 1
        g["total_chars"] += chars
        g["max_chars"] = max(int(g["max_chars"]), chars)
        g["total_lines"] += int(row.get("output_lines") or 0)
        if row.get("root_title"):
            g["tasks"].add(str(row.get("root_title")))
        if g["example"] is None or chars > int(g["example"].get("output_chars") or 0):
            g["example"] = row

    out: list[dict[str, Any]] = []
    for g in groups.values():
        ex = g["example"] or {}
        count = int(g["count"])
        total_chars = int(g["total_chars"])
        max_chars = int(g["max_chars"])
        out.append(
            {
                "tool_name": g["tool_name"],
                "content_kind": g["content_kind"],
                "count": count,
                "total_chars": total_chars,
                "max_chars": max_chars,
                "avg_chars": round(total_chars / count) if count else 0,
                "total_lines": int(g["total_lines"]),
                "affected_tasks": len(g["tasks"]),
                "example_task": ex.get("root_title", ""),
                "example_message_id": ex.get("message_id", ""),
                "example_session_id": ex.get("session_id", ""),
                "example_sample": ex.get("sample", ""),
                "recommended_mitigation": mitigation_for(str(g["tool_name"]), str(g["content_kind"])),
                "pattern_priority": pattern_priority(total_chars, count, max_chars),
            }
        )
    priority_order = {"high": 0, "medium": 1, "low": 2}
    out.sort(key=lambda r: (priority_order.get(str(r["pattern_priority"]), 9), -int(r["total_chars"]), -int(r["count"])))
    return out


def extract_skill_name(content: str) -> str:
    try:
        obj = json.loads(content)
        return obj.get("name") or "(unknown)"
    except Exception:
        m = re.search(r'"name"\s*:\s*"([^"]+)"', content or "")
        return m.group(1) if m else "(unknown)"


DRIVER_ACTIONS = {
    "api-loop-heavy": "Split phases; make a working summary, then continue in a fresh session.",
    "context-heavy": "Reduce carried context; save raw findings to files and continue from a compact summary.",
    "terminal-heavy": "Filter terminal output, avoid raw HTML/log dumps, and save large raw output to files.",
    "skill-heavy": "Use smaller task-specific references or summarize loaded skills before continuing.",
    "search-heavy": "Stage file discovery with count/files_only before targeted read_file(offset, limit).",
    "web-heavy": "Prefer targeted web_extract/browser steps and avoid broad repeated searches.",
    "browser-heavy": "Capture only relevant browser state/console output; avoid repeated full snapshots.",
    "tool-heavy": "Batch mechanical inspection into scripts that return compact summaries.",
    "subagent-heavy": "Use subagents only for independent work and keep child summaries compact.",
    "general-heavy": "Review whether the work produced a durable artifact; split or summarize if continuing.",
}


def classify_driver(row: dict[str, Any], tool_chars: Counter[str]) -> tuple[str, str, str]:
    """Classify why a session/group looks expensive.

    Heuristics are intentionally simple and review-oriented. They explain where
    to look first; they are not proof that a session was wasteful.
    """
    total = int(row.get("total_tokens") or 0)
    api = int(row.get("api_calls") or 0)
    tools = int(row.get("tool_calls") or 0)
    tpa = round(total / api) if api else 0

    terminal_chars = tool_chars.get("terminal", 0)
    skill_chars = tool_chars.get("skill_view", 0)
    search_chars = tool_chars.get("search_files", 0) + tool_chars.get("read_file", 0)
    web_chars = tool_chars.get("web_search", 0) + tool_chars.get("web_extract", 0)
    browser_chars = sum(v for k, v in tool_chars.items() if k.startswith("browser_"))
    subagent_chars = tool_chars.get("delegate_task", 0)

    candidates: list[tuple[float, str, str]] = []
    if api >= 150:
        candidates.append((api / 150, "api-loop-heavy", f"api_calls={api}"))
    if tpa >= 120_000:
        candidates.append((tpa / 120_000, "context-heavy", f"tokens_per_api={tpa}"))
    if terminal_chars >= 300_000:
        candidates.append((terminal_chars / 300_000, "terminal-heavy", f"terminal_chars={terminal_chars}"))
    if skill_chars >= 150_000:
        candidates.append((skill_chars / 150_000, "skill-heavy", f"skill_view_chars={skill_chars}"))
    if search_chars >= 300_000:
        candidates.append((search_chars / 300_000, "search-heavy", f"read/search_chars={search_chars}"))
    if web_chars >= 300_000:
        candidates.append((web_chars / 300_000, "web-heavy", f"web_chars={web_chars}"))
    if browser_chars >= 200_000:
        candidates.append((browser_chars / 200_000, "browser-heavy", f"browser_chars={browser_chars}"))
    if tools >= 150:
        candidates.append((tools / 150, "tool-heavy", f"tool_calls={tools}"))
    if subagent_chars >= 50_000:
        candidates.append((subagent_chars / 50_000, "subagent-heavy", f"delegate_task_chars={subagent_chars}"))

    if not candidates:
        return "general-heavy", f"total_tokens={total}; api_calls={api}; tool_calls={tools}", DRIVER_ACTIONS["general-heavy"]

    candidates.sort(reverse=True)
    primary = candidates[0][1]
    top_notes = [note for _, _, note in candidates[:3]]
    top_tools = ", ".join(f"{k}:{v}" for k, v in tool_chars.most_common(3) if v)
    notes = "; ".join(top_notes)
    if top_tools:
        notes = f"{notes}; top_tools={top_tools}"
    return primary, notes, DRIVER_ACTIONS[primary]


def slugify_title(title: str, max_len: int = 48) -> str:
    slug = re.sub(r"[^0-9A-Za-zぁ-んァ-ン一-龥_-]+", "-", title).strip("-")
    slug = re.sub(r"-+", "-", slug)
    return (slug or "untitled")[:max_len]


def make_queue_id(row: dict[str, Any]) -> str:
    key = "|".join(
        str(row.get(k) or "")
        for k in ["root_title", "first_started_at", "last_started_at", "total_tokens"]
    )
    return hashlib.sha1(key.encode("utf-8")).hexdigest()[:12]


def build_summary_paths(row: dict[str, Any], tmp_dir: Path, org_dir: Path) -> tuple[str, str]:
    title = str(row.get("root_title") or row.get("title") or "untitled")
    today = dt.datetime.now().strftime("%Y-%m-%d")
    filename = f"{today}-{slugify_title(title)}.md"
    return str(tmp_dir / filename), str(org_dir.expanduser() / filename)


def priority_counts(rows: Iterable[dict[str, Any]]) -> Counter[str]:
    c: Counter[str] = Counter()
    for r in rows:
        c[str(r.get("summary_priority") or r.get("priority") or "unknown")] += 1
    return c


def render_summary_stub(row: dict[str, Any]) -> str:
    now = dt.datetime.now().strftime("%Y-%m-%d")
    title = row.get("task_title") or row.get("root_title") or "untitled"
    return f"""# Heavy Task Summary: {title}

> これは自動生成された作業用stubです。知識管理用の完成ノートではありません。
> 作業候補: `{row.get('suggested_org_summary_path', '')}`。curated PIMへの昇格は明示的な承認後だけ行ってください。

作成日: {now}
元session/group: {title}
保存方針: auto-generated local working stub; do not promote automatically.

## 1. Goal

- TODO: この作業で達成したかったことを書く。

## 2. Outcome

- TODO: 実際に達成したことを書く。

## 3. Key Findings

- TODO: 次回読むべき要点を書く。生ログや長い引用は貼らない。

## 4. Decisions

- TODO: 決定事項を書く。

## 5. Durable Artifacts

- Scripts:
- Configs:
- Reports:
- Skills:
- Cron jobs:
- Other files:

## 6. Raw Data / Logs

- TODO: 大きい出力やCSVの保存先を書く。

## 7. Usage Diagnosis

- queue_id: {row.get('queue_id', '')}
- total tokens: {row.get('total_tokens', '')}
- API calls: {row.get('api_calls', '')}
- tokens/API: {row.get('tokens_per_api_call', '')}
- primary_driver: {row.get('primary_driver', '')}
- summary_priority: {row.get('priority', '')}
- summary_reason: {row.get('summary_reason', '')}
- recommended_action: {row.get('recommended_action', '')}
- avoid next time:

## 8. Commands Verified

```bash

```

## 9. Next Session Starter

```text
TODO: 次回この作業を軽く再開するための短いプロンプトを書く。
```

## 10. Reuse Potential

- [ ] skill化する
- [ ] script化する
- [ ] cron/定期workflowに入れる
- [ ] weekly report / org / PIM に反映する
- [ ] いったん不要

## 11. Next Automation Candidates

1. TODO

## 12. Template Feedback

- TODO

Notes:

- Auto-generated from `summary_queue.csv`; status starts as `pending`.
"""


def write_summary_stubs(rows: list[dict[str, Any]], priorities: set[str], max_count: int, explicit_queue_ids: set[str] | None = None) -> list[str]:
    written: list[str] = []
    explicit_queue_ids = explicit_queue_ids or set()
    for row in rows:
        explicit = str(row.get("queue_id")) in explicit_queue_ids
        if not explicit and max_count >= 0 and len(written) >= max_count:
            if explicit_queue_ids:
                continue
            break
        if not explicit and str(row.get("priority")) not in priorities:
            continue
        if row.get("existing_summary_found") == "true":
            continue
        path = Path(str(row.get("suggested_tmp_summary_path") or "")).expanduser()
        if not path:
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            # Do not clobber user edits or a previous stub.
            continue
        path.write_text(render_summary_stub(row), encoding="utf-8")
        written.append(str(path))
    return written


def build_next_actions(
    *,
    summary_queue_rows: list[dict[str, Any]],
    tool_output_pattern_rows: list[dict[str, Any]],
    outdir: Path,
    days: int,
) -> list[dict[str, Any]]:
    """Return a small, low-burden action queue for usage hygiene.

    The goal is not to auto-curate notes or hard-stop expensive work. It is to
    make the weekly no-agent report actionable by surfacing 1-3 concrete next
    steps that preserve user control: create a tmp handoff for the biggest
    resumable task, switch recurring broad search to the lightweight funnel, or
    compact a recurring large-output pattern.
    """
    actions: list[dict[str, Any]] = []

    pending = [r for r in summary_queue_rows if r.get("status") == "pending"]
    priority_order = {"high": 0, "medium": 1, "low": 2}
    pending.sort(key=lambda r: (priority_order.get(str(r.get("priority")), 9), -int(r.get("total_tokens") or 0)))
    if pending:
        row = pending[0]
        queue_id = str(row.get("queue_id") or "")
        actions.append(
            {
                "priority": "high" if row.get("priority") == "high" else "medium",
                "kind": "tmp-handoff-stub",
                "title": f"Create tmp handoff stub for: {row.get('task_title', '')}",
                "rationale": f"{row.get('priority')} summary candidate; {fmt_int(row.get('total_tokens'))} tokens; driver={row.get('primary_driver')}",
                "command": f"~/.hermes/scripts/hermes_usage_analyzer.py --days {days} --outdir {outdir} --make-summary-stub {queue_id}",
                "target": str(row.get("suggested_tmp_summary_path") or ""),
                "human_confirmation": "not required for tmp stub; required before promoting to org/PIM",
            }
        )

    for pat in tool_output_pattern_rows:
        tool = str(pat.get("tool_name") or "")
        kind = str(pat.get("content_kind") or "")
        priority = str(pat.get("pattern_priority") or "")
        if tool == "session_search" and kind == "search-results" and priority in {"high", "medium"}:
            actions.append(
                {
                    "priority": priority,
                    "kind": "session-search-funnel",
                    "title": "Use lightweight past-session search funnel before broad session_search",
                    "rationale": f"{pat.get('count')} large session_search outputs; {fmt_int(pat.get('total_chars'))} chars total",
                    "command": "~/.hermes/scripts/session_candidates.py \"<query>\" --limit 5 && ~/.hermes/scripts/session_window.py <session_id> <message_id> --window 3 --roles user,assistant",
                    "target": "agent/tool-use habit",
                    "human_confirmation": "not required",
                }
            )
            break

    for pat in tool_output_pattern_rows:
        tool = str(pat.get("tool_name") or "")
        kind = str(pat.get("content_kind") or "")
        priority = str(pat.get("pattern_priority") or "")
        if tool == "terminal" and kind in {"json", "html", "terminal-log", "test-log"} and priority in {"high", "medium"}:
            actions.append(
                {
                    "priority": priority,
                    "kind": "compact-terminal-output",
                    "title": "Wrap risky terminal commands with compact_command/html_brief",
                    "rationale": f"{pat.get('count')} large terminal {kind} outputs; max {fmt_int(pat.get('max_chars'))} chars",
                    "command": "~/.hermes/scripts/compact_command.py -- <command>  # or ~/.hermes/scripts/html_brief.py <url-or-file>",
                    "target": "agent/tool-use habit",
                    "human_confirmation": "not required",
                }
            )
            break

    return actions[:3]


def scan_existing_summaries(dirs_csv: str) -> list[Path]:
    paths: list[Path] = []
    for raw in str(dirs_csv or "").split(","):
        root = Path(raw.strip()).expanduser()
        if not root.exists():
            continue
        if root.is_file() and root.suffix.lower() in {".md", ".org"}:
            paths.append(root)
            continue
        if root.is_dir():
            for pattern in ("*.md", "*.org"):
                paths.extend(p for p in root.rglob(pattern) if p.is_file())
    return sorted(set(paths))


def find_existing_summary(row: dict[str, Any], existing_paths: list[Path]) -> str:
    explicit_paths = [
        row.get("suggested_tmp_summary_path"),
        row.get("suggested_org_summary_path"),
        row.get("suggested_summary_path"),
    ]
    for raw in explicit_paths:
        if raw and Path(str(raw)).expanduser().exists():
            return str(Path(str(raw)).expanduser())
    slug = str(row.get("task_slug") or slugify_title(str(row.get("task_title") or row.get("root_title") or "")))
    title = str(row.get("task_title") or row.get("root_title") or "")
    tokens = [t for t in {slug, title} if t]
    for p in existing_paths:
        name = p.name
        if any(token and token in name for token in tokens):
            return str(p)
    return ""


def summary_recommendation(row: dict[str, Any], template_path: str, summary_dir: str) -> tuple[str, str, str, str]:
    total = int(row.get("total_tokens") or 0)
    api = int(row.get("api_calls") or 0)
    tpa = int(row.get("tokens_per_api_call") or 0)
    tools = int(row.get("tool_calls") or 0)
    driver = str(row.get("primary_driver") or "")

    reasons: list[str] = []
    priority = ""
    if total >= 10_000_000 and api >= 100:
        priority = "high"
        reasons.append("total>=10M and api_calls>=100")
    elif total >= 10_000_000:
        priority = "high"
        reasons.append("total>=10M")
    elif tpa >= 100_000 or driver in {"terminal-heavy", "skill-heavy", "search-heavy", "api-loop-heavy", "context-heavy"}:
        priority = "medium"
        if tpa >= 100_000:
            reasons.append("tokens_per_api>=100k")
        if driver:
            reasons.append(f"driver={driver}")
    elif tools >= 150:
        priority = "low"
        reasons.append("tool_calls>=150")

    if not priority:
        return "false", "", "", ""

    title = str(row.get("root_title") or row.get("title") or "untitled")
    today = dt.datetime.now().strftime("%Y-%m-%d")
    suggested = Path(summary_dir).expanduser() / f"{today}-{slugify_title(title)}.md"
    return "true", priority, ";".join(reasons), str(suggested)


def main() -> int:
    args = parse_args()
    try:
        profile, db_path = resolve_db_source(db=args.db, profile=args.profile)
    except ValueError as error:
        raise SystemExit(str(error)) from error
    args.db = str(db_path)
    con = open_db(args.db)
    cutoff = dt.datetime.now().timestamp() - args.days * 86400
    now_day = dt.datetime.now().strftime("%Y-%m-%d")
    outdir = Path(args.outdir).expanduser() if args.outdir else Path("~/tmp/hermes-usage").expanduser() / now_day
    outdir.mkdir(parents=True, exist_ok=True)
    summary_tmp_dir = Path(args.summary_tmp_dir).expanduser() if args.summary_tmp_dir else outdir / "summary-stubs"
    summary_org_dir = Path(args.summary_dir).expanduser()
    existing_summary_paths = scan_existing_summaries(args.existing_summary_dirs)

    sessions = con.execute(
        """
        select id,parent_session_id,source,title,started_at,ended_at,message_count,tool_call_count,api_call_count,
               model,billing_provider,billing_mode,cost_status,
               coalesce(input_tokens,0) input_tokens,
               coalesce(output_tokens,0) output_tokens,
               coalesce(cache_read_tokens,0) cache_read_tokens,
               coalesce(cache_write_tokens,0) cache_write_tokens,
               coalesce(reasoning_tokens,0) reasoning_tokens
        from sessions
        where coalesce(archived,0)=0 and started_at >= ?
        order by started_at
        """,
        (cutoff,),
    ).fetchall()
    by_id = {r["id"]: r for r in sessions}

    def root_title(r: sqlite3.Row) -> str:
        parent = by_id.get(r["parent_session_id"] or "")
        if r["source"] == "subagent" and parent is not None:
            return base_title(parent["title"])
        return base_title(r["title"])

    session_rows: list[dict[str, Any]] = []
    for r in sessions:
        session_rows.append(
            {
                "session_id": r["id"],
                "parent_session_id": r["parent_session_id"] or "",
                "root_title": root_title(r),
                "title": r["title"] or "",
                "source": r["source"],
                "started_at": iso(r["started_at"]),
                "total_tokens": total_tokens(r),
                "input_tokens": r["input_tokens"],
                "output_tokens": r["output_tokens"],
                "cache_read_tokens": r["cache_read_tokens"],
                "cache_write_tokens": r["cache_write_tokens"],
                "reasoning_tokens": r["reasoning_tokens"],
                "api_calls": r["api_call_count"] or 0,
                "tool_calls": r["tool_call_count"] or 0,
                "messages": r["message_count"] or 0,
                "billing_provider": r["billing_provider"] or "",
                "billing_mode": r["billing_mode"] or "",
                "cost_status": r["cost_status"] or "",
            }
        )

    groups: dict[str, Counter] = defaultdict(Counter)
    meta: dict[str, dict[str, Any]] = {}
    for r in session_rows:
        title = r["root_title"]
        g = groups[title]
        g["sessions"] += 1
        g["subagents"] += 1 if r["source"] == "subagent" else 0
        for k in [
            "total_tokens",
            "input_tokens",
            "output_tokens",
            "cache_read_tokens",
            "cache_write_tokens",
            "reasoning_tokens",
            "api_calls",
            "tool_calls",
            "messages",
        ]:
            g[k] += int(r[k] or 0)
        m = meta.setdefault(title, {"first": r["started_at"], "last": r["started_at"], "sources": Counter()})
        m["first"] = min(m["first"], r["started_at"])
        m["last"] = max(m["last"], r["started_at"])
        m["sources"][r["source"]] += 1

    group_rows = []
    for title, g in groups.items():
        api = int(g["api_calls"] or 0)
        total = int(g["total_tokens"] or 0)
        group_rows.append(
            {
                "root_title": title,
                "total_tokens": total,
                "tokens_per_api_call": round(total / api) if api else 0,
                "sessions": int(g["sessions"]),
                "subagents": int(g["subagents"]),
                "input_tokens": int(g["input_tokens"]),
                "output_tokens": int(g["output_tokens"]),
                "cache_read_tokens": int(g["cache_read_tokens"]),
                "cache_share": f"{int(g['cache_read_tokens']) / total:.3f}" if total else "0",
                "reasoning_tokens": int(g["reasoning_tokens"]),
                "api_calls": api,
                "tool_calls": int(g["tool_calls"]),
                "messages": int(g["messages"]),
                "first_started_at": meta[title]["first"],
                "last_started_at": meta[title]["last"],
                "sources": ";".join(f"{k}:{v}" for k, v in meta[title]["sources"].items()),
            }
        )
    group_rows.sort(key=lambda r: int(r["total_tokens"]), reverse=True)

    ids = [r["session_id"] for r in session_rows]
    tool_rows: list[dict[str, Any]] = []
    skill_rows: list[dict[str, Any]] = []
    session_tool_chars: dict[str, Counter[str]] = defaultdict(Counter)
    if ids:
        q = ",".join("?" for _ in ids)
        for r in con.execute(
            f"""
            select session_id, tool_name, sum(length(coalesce(content,''))) output_chars
            from messages
            where session_id in ({q}) and tool_name is not null
            group by session_id, tool_name
            """,
            ids,
        ):
            session_tool_chars[r["session_id"]][r["tool_name"]] = int(r["output_chars"] or 0)

        for r in con.execute(
            f"""
            select tool_name, count(*) calls, sum(length(coalesce(content,''))) output_chars,
                   avg(length(coalesce(content,''))) avg_chars
            from messages
            where session_id in ({q}) and tool_name is not null
            group by tool_name
            order by output_chars desc
            """,
            ids,
        ):
            tool_rows.append({"tool_name": r["tool_name"], "calls": r["calls"], "output_chars": r["output_chars"] or 0, "avg_chars": round(r["avg_chars"] or 0)})

        skill_counts: Counter[str] = Counter()
        skill_chars: Counter[str] = Counter()
        for r in con.execute(f"select content from messages where session_id in ({q}) and tool_name='skill_view'", ids):
            content = r["content"] or ""
            name = extract_skill_name(content)
            skill_counts[name] += 1
            skill_chars[name] += len(content)
        for name, calls in skill_counts.most_common():
            skill_rows.append({"skill_name": name, "loads": calls, "output_chars": skill_chars[name], "avg_chars": round(skill_chars[name] / calls) if calls else 0})

    session_meta = {r["session_id"]: r for r in session_rows}
    large_tool_rows: list[dict[str, Any]] = []
    if ids and args.large_tool_threshold > 0:
        for r in con.execute(
            f"""
            select id,session_id,tool_name,timestamp,
                   length(coalesce(content,'')) output_chars,
                   content
            from messages
            where session_id in ({q})
              and tool_name is not null
              and length(coalesce(content,'')) >= ?
            order by output_chars desc
            """,
            ids + [args.large_tool_threshold],
        ):
            meta = session_meta.get(r["session_id"], {})
            content = r["content"] or ""
            kind = classify_content_kind(r["tool_name"] or "", content)
            large_tool_rows.append(
                {
                    "message_id": r["id"],
                    "session_id": r["session_id"],
                    "root_title": meta.get("root_title", ""),
                    "title": meta.get("title", ""),
                    "source": meta.get("source", ""),
                    "started_at": meta.get("started_at", ""),
                    "tool_name": r["tool_name"] or "",
                    "output_chars": r["output_chars"] or 0,
                    "output_lines": content.count("\n") + (1 if content else 0),
                    "content_kind": kind,
                    "recommended_mitigation": mitigation_for(r["tool_name"] or "", kind),
                    "sample": compact_sample(content, args.large_tool_sample_chars),
                }
            )

    tool_output_pattern_rows = build_tool_output_patterns(large_tool_rows)

    group_tool_chars: dict[str, Counter[str]] = defaultdict(Counter)
    for r in session_rows:
        group_tool_chars[r["root_title"]].update(session_tool_chars.get(r["session_id"], Counter()))
    for gr in group_rows:
        primary, notes, action = classify_driver(gr, group_tool_chars.get(gr["root_title"], Counter()))
        gr["primary_driver"] = primary
        gr["driver_notes"] = notes
        gr["recommended_action"] = action
        summary_rec, priority, reason, suggested_path = summary_recommendation(
            gr, args.summary_template, args.summary_dir
        )
        gr["summary_recommended"] = summary_rec
        gr["summary_priority"] = priority
        gr["summary_reason"] = reason
        gr["summary_template_path"] = str(Path(args.summary_template).expanduser()) if summary_rec == "true" else ""
        gr["suggested_summary_path"] = suggested_path
        if summary_rec == "true":
            tmp_path, org_path = build_summary_paths(gr, summary_tmp_dir, summary_org_dir)
        else:
            tmp_path, org_path = "", ""
        gr["suggested_tmp_summary_path"] = tmp_path
        gr["suggested_org_summary_path"] = org_path

    suspicious = []
    # Heuristics tuned for weekly review, not hard correctness claims.
    for r in session_rows:
        total = int(r["total_tokens"])
        api = int(r["api_calls"])
        tpa = round(total / api) if api else 0
        reasons = []
        if total >= 10_000_000:
            reasons.append("total>=10M")
        if api >= 100:
            reasons.append("api_calls>=100")
        if tpa >= 100_000:
            reasons.append("tokens_per_api>=100k")
        if int(r["tool_calls"]) >= 150:
            reasons.append("tool_calls>=150")
        if reasons:
            primary, notes, action = classify_driver(r, session_tool_chars.get(r["session_id"], Counter()))
            candidate = {
                **r,
                "tokens_per_api_call": tpa,
                "reasons": ";".join(reasons),
                "primary_driver": primary,
                "driver_notes": notes,
                "recommended_action": action,
            }
            summary_rec, priority, reason, suggested_path = summary_recommendation(
                candidate, args.summary_template, args.summary_dir
            )
            candidate.update(
                {
                    "summary_recommended": summary_rec,
                    "summary_priority": priority,
                    "summary_reason": reason,
                    "summary_template_path": str(Path(args.summary_template).expanduser()) if summary_rec == "true" else "",
                    "suggested_summary_path": suggested_path,
                    "suggested_tmp_summary_path": build_summary_paths(candidate, summary_tmp_dir, summary_org_dir)[0] if summary_rec == "true" else "",
                    "suggested_org_summary_path": build_summary_paths(candidate, summary_tmp_dir, summary_org_dir)[1] if summary_rec == "true" else "",
                }
            )
            suspicious.append(candidate)
    suspicious.sort(key=lambda r: int(r["total_tokens"]), reverse=True)

    priority_order = {"high": 0, "medium": 1, "low": 2}
    created_at = iso(dt.datetime.now().timestamp())
    summary_queue_rows: list[dict[str, Any]] = []
    for r in sorted(
        [row for row in group_rows if row.get("summary_recommended") == "true"],
        key=lambda row: (priority_order.get(str(row.get("summary_priority")), 9), -int(row.get("total_tokens") or 0)),
    ):
        title = str(r.get("root_title") or "untitled")
        queue_row = {
            "queue_id": make_queue_id(r),
            "task_title": title,
            "task_slug": slugify_title(title),
            "priority": r.get("summary_priority", ""),
            "primary_driver": r.get("primary_driver", ""),
            "summary_reason": r.get("summary_reason", ""),
            "total_tokens": r.get("total_tokens", ""),
            "api_calls": r.get("api_calls", ""),
            "tokens_per_api_call": r.get("tokens_per_api_call", ""),
            "tool_calls": r.get("tool_calls", ""),
            "sessions": r.get("sessions", ""),
            "subagents": r.get("subagents", ""),
            "suggested_tmp_summary_path": r.get("suggested_tmp_summary_path", ""),
            "suggested_org_summary_path": r.get("suggested_org_summary_path", ""),
            "summary_template_path": r.get("summary_template_path", ""),
            "recommended_action": r.get("recommended_action", ""),
            "status": "pending",
            "decision": "",
            "notes": "",
            "created_at": created_at,
        }
        existing_path = find_existing_summary(queue_row, existing_summary_paths)
        queue_row["existing_summary_found"] = "true" if existing_path else "false"
        queue_row["existing_summary_path"] = existing_path
        if existing_path:
            queue_row["status"] = "done"
            queue_row["decision"] = "existing_summary_found"
        summary_queue_rows.append(queue_row)

    stub_priorities = {p.strip() for p in str(args.summary_stub_priorities).split(",") if p.strip()}
    explicit_queue_ids = {q.strip() for q in str(args.make_summary_stub).split(",") if q.strip()}
    auto_stub_limit = args.max_summary_stubs if args.write_summary_stubs else 0
    written_stubs = write_summary_stubs(summary_queue_rows, stub_priorities, auto_stub_limit, explicit_queue_ids) if (args.write_summary_stubs or explicit_queue_ids) else []

    write_csv(
        outdir / "sessions.csv",
        session_rows,
        [
            "session_id",
            "parent_session_id",
            "root_title",
            "title",
            "source",
            "started_at",
            "total_tokens",
            "input_tokens",
            "output_tokens",
            "cache_read_tokens",
            "cache_write_tokens",
            "reasoning_tokens",
            "api_calls",
            "tool_calls",
            "messages",
            "billing_provider",
            "billing_mode",
            "cost_status",
        ],
    )
    write_csv(
        outdir / "task_groups.csv",
        group_rows,
        [
            "root_title",
            "total_tokens",
            "tokens_per_api_call",
            "sessions",
            "subagents",
            "input_tokens",
            "output_tokens",
            "cache_read_tokens",
            "cache_share",
            "reasoning_tokens",
            "api_calls",
            "tool_calls",
            "messages",
            "primary_driver",
            "driver_notes",
            "recommended_action",
            "summary_recommended",
            "summary_priority",
            "summary_reason",
            "summary_template_path",
            "suggested_summary_path",
            "suggested_tmp_summary_path",
            "suggested_org_summary_path",
            "first_started_at",
            "last_started_at",
            "sources",
        ],
    )
    write_csv(outdir / "tools.csv", tool_rows, ["tool_name", "calls", "output_chars", "avg_chars"])
    write_csv(outdir / "skills.csv", skill_rows, ["skill_name", "loads", "output_chars", "avg_chars"])
    write_csv(
        outdir / "large_tool_outputs.csv",
        large_tool_rows,
        [
            "message_id",
            "session_id",
            "root_title",
            "title",
            "source",
            "started_at",
            "tool_name",
            "output_chars",
            "output_lines",
            "content_kind",
            "recommended_mitigation",
            "sample",
        ],
    )
    write_csv(
        outdir / "tool_output_patterns.csv",
        tool_output_pattern_rows,
        [
            "tool_name",
            "content_kind",
            "count",
            "total_chars",
            "max_chars",
            "avg_chars",
            "total_lines",
            "affected_tasks",
            "example_task",
            "example_message_id",
            "example_session_id",
            "example_sample",
            "recommended_mitigation",
            "pattern_priority",
        ],
    )
    write_csv(
        outdir / "suspicious_sessions.csv",
        suspicious,
        [
            "session_id",
            "root_title",
            "title",
            "source",
            "started_at",
            "total_tokens",
            "tokens_per_api_call",
            "api_calls",
            "tool_calls",
            "messages",
            "reasons",
            "primary_driver",
            "driver_notes",
            "recommended_action",
            "summary_recommended",
            "summary_priority",
            "summary_reason",
            "summary_template_path",
            "suggested_summary_path",
            "suggested_tmp_summary_path",
            "suggested_org_summary_path",
        ],
    )
    write_csv(
        outdir / "summary_queue.csv",
        summary_queue_rows,
        [
            "queue_id",
            "task_title",
            "task_slug",
            "priority",
            "primary_driver",
            "summary_reason",
            "total_tokens",
            "api_calls",
            "tokens_per_api_call",
            "tool_calls",
            "sessions",
            "subagents",
            "suggested_tmp_summary_path",
            "suggested_org_summary_path",
            "summary_template_path",
            "recommended_action",
            "existing_summary_found",
            "existing_summary_path",
            "status",
            "decision",
            "notes",
            "created_at",
        ],
    )
    next_actions = build_next_actions(
        summary_queue_rows=summary_queue_rows,
        tool_output_pattern_rows=tool_output_pattern_rows,
        outdir=outdir,
        days=args.days,
    )
    write_csv(
        outdir / "next_actions.csv",
        next_actions,
        ["priority", "kind", "title", "rationale", "command", "target", "human_confirmation"],
    )

    totals = Counter()
    for r in session_rows:
        for k in ["total_tokens", "input_tokens", "output_tokens", "cache_read_tokens", "cache_write_tokens", "reasoning_tokens", "api_calls", "tool_calls", "messages"]:
            totals[k] += int(r[k] or 0)
    sources = Counter(r["source"] for r in session_rows)

    top_groups_md_rows = [
        [
            r["root_title"][:60],
            fmt_int(r["total_tokens"]),
            fmt_int(r["tokens_per_api_call"]),
            r["api_calls"],
            r["tool_calls"],
            r["sessions"],
            r["subagents"],
            f"{float(r['cache_share']):.1%}",
            r["primary_driver"],
        ]
        for r in group_rows[: args.top]
    ]
    top_tools_md_rows = [[r["tool_name"], r["calls"], fmt_int(r["output_chars"]), fmt_int(r["avg_chars"])] for r in tool_rows[: args.top]]
    top_skills_md_rows = [[r["skill_name"], r["loads"], fmt_int(r["output_chars"]), fmt_int(r["avg_chars"])] for r in skill_rows[: args.top]]
    large_tool_md_rows = [
        [
            r["root_title"][:45],
            r["tool_name"],
            fmt_int(r["output_chars"]),
            fmt_int(r["output_lines"]),
            r["content_kind"],
            r["recommended_mitigation"][:75],
        ]
        for r in large_tool_rows[: args.top]
    ]
    tool_pattern_md_rows = [
        [
            r["tool_name"],
            r["content_kind"],
            r["count"],
            fmt_int(r["total_chars"]),
            fmt_int(r["max_chars"]),
            r["affected_tasks"],
            r["pattern_priority"],
            r["recommended_mitigation"][:75],
        ]
        for r in tool_output_pattern_rows[: args.top]
    ]
    suspicious_md_rows = [
        [
            r["root_title"][:50],
            r["source"],
            fmt_int(r["total_tokens"]),
            fmt_int(r["tokens_per_api_call"]),
            r["api_calls"],
            r["tool_calls"],
            r["primary_driver"],
            r["reasons"],
            r["recommended_action"][:70],
        ]
        for r in suspicious[: args.top]
    ]
    summary_recs = [r for r in group_rows if r.get("summary_recommended") == "true"]
    priority_order = {"high": 0, "medium": 1, "low": 2}
    summary_recs.sort(key=lambda r: (priority_order.get(str(r.get("summary_priority")), 9), -int(r.get("total_tokens") or 0)))
    summary_rec_md_rows = [
        [
            r["root_title"][:55],
            r["summary_priority"],
            fmt_int(r["total_tokens"]),
            r["primary_driver"],
            r["summary_reason"],
            r["suggested_tmp_summary_path"],
            r["suggested_org_summary_path"],
        ]
        for r in summary_recs[: args.top]
    ]
    queue_counts = priority_counts(summary_queue_rows)
    summary_queue_count_rows = [[p, queue_counts.get(p, 0)] for p in ["high", "medium", "low"] if queue_counts.get(p, 0)]
    existing_summary_count = sum(1 for r in summary_queue_rows if r.get("existing_summary_found") == "true")
    pending_summary_count = sum(1 for r in summary_queue_rows if r.get("status") == "pending")
    next_action_md_rows = [
        [
            r.get("priority", ""),
            r.get("kind", ""),
            r.get("title", ""),
            r.get("rationale", ""),
            r.get("command", ""),
        ]
        for r in next_actions
    ]

    md = f"""# Hermes / Codex usage report

Generated: {iso(dt.datetime.now().timestamp())}
Lookback: last {args.days} days
Profile: `{profile}`
Database: `{db_path}`

This is local Hermes accounting from `state.db`, not the official Codex quota source. Official Codex analytics: <https://chatgpt.com/codex/cloud/settings/analytics>

## Summary

| Metric | Value |
|---|---:|
| Sessions | {fmt_int(len(session_rows))} |
| Sources | {', '.join(f'{k}:{v}' for k, v in sources.items()) or '-'} |
| Messages | {fmt_int(totals['messages'])} |
| Tool calls | {fmt_int(totals['tool_calls'])} |
| API calls | {fmt_int(totals['api_calls'])} |
| Input tokens | {fmt_int(totals['input_tokens'])} |
| Output tokens | {fmt_int(totals['output_tokens'])} |
| Cache read tokens | {fmt_int(totals['cache_read_tokens'])} |
| Total recorded tokens | {fmt_int(totals['total_tokens'])} |
| Reasoning tokens | {fmt_int(totals['reasoning_tokens'])} |
| Cache share | {fmt_pct(totals['cache_read_tokens'], totals['total_tokens'])} |

## Top task groups

Subagent sessions are rolled up to their parent task when the parent exists.

{md_table(['Task', 'Total tokens', 'Tokens/API', 'API', 'Tools', 'Sessions', 'Subagents', 'Cache share', 'Primary driver'], top_groups_md_rows)}

## Top tools by output volume

{md_table(['Tool', 'Calls', 'Output chars', 'Avg chars/call'], top_tools_md_rows)}

## Top loaded skills by output volume

{md_table(['Skill', 'Loads', 'Output chars', 'Avg chars/load'], top_skills_md_rows)}

## Tool output bloat patterns

Aggregated from `large_tool_outputs.csv` by `tool_name + content_kind`. Full list: `tool_output_patterns.csv`.

{md_table(['Tool', 'Kind', 'Count', 'Total chars', 'Max chars', 'Tasks', 'Priority', 'Mitigation'], tool_pattern_md_rows)}

## Large tool outputs

Rows with tool output >= {fmt_int(args.large_tool_threshold)} chars. Full list: `large_tool_outputs.csv`. Samples in CSV are redacted and truncated to {fmt_int(args.large_tool_sample_chars)} chars.

{md_table(['Task', 'Tool', 'Chars', 'Lines', 'Kind', 'Mitigation'], large_tool_md_rows)}

## Suspicious / review-worthy sessions

Heuristics: total>=10M, api_calls>=100, tokens_per_api>=100k, or tool_calls>=150.

{md_table(['Task', 'Source', 'Total tokens', 'Tokens/API', 'API', 'Tools', 'Driver', 'Reasons', 'Recommended action'], suspicious_md_rows)}

## Recommended heavy-task summaries

Create these only when the task produced reusable knowledge or you expect to resume it. Template: `{Path(args.summary_template).expanduser()}`

{md_table(['Task', 'Priority', 'Total tokens', 'Driver', 'Reason', 'Tmp stub path', 'Org promotion path'], summary_rec_md_rows)}

## Summary queue

Wrote `summary_queue.csv` with {len(summary_queue_rows)} items: {pending_summary_count} pending, {existing_summary_count} already matched to an existing summary. Automatic stubs are working artifacts under tmp, not curated knowledge notes.

{md_table(['Priority', 'Count'], summary_queue_count_rows)}

Stub generation: {'enabled' if args.write_summary_stubs else 'disabled'}; written stubs: {len(written_stubs)}.

## Next suggested actions

These are low-burden guardrails generated from `summary_queue.csv` and `tool_output_patterns.csv`. They do not promote anything into curated PIM storage automatically.

{md_table(['Priority', 'Kind', 'Action', 'Rationale', 'Command'], next_action_md_rows)}

## Interpretation guide

- `total_tokens` is `input + output + cache_read + cache_write`.
- High `tokens/API` means each model call carried a large effective context.
- High `cache_share` means prompt caching is helping, but the same large context is still repeatedly involved.
- Large tool output is costly because it remains in the conversation and affects later turns.

## Default mitigation checklist

1. Split independent phases into fresh sessions.
2. Save raw large data to files; return compact summaries to the model.
3. Use `search_files(..., output_mode='count'/'files_only')` before reading matches.
4. Use `read_file(offset, limit)` narrowly.
5. Avoid raw HTML/log dumps via terminal; prefer `web_extract` or filtered command output.
6. Use subagents for isolation/parallelism, not as a way to reduce total Codex usage.
7. Convert repeated heavy workflows into compact scripts or skills.

## Output files

- `sessions.csv`
- `task_groups.csv`
- `tools.csv`
- `skills.csv`
- `large_tool_outputs.csv`
- `tool_output_patterns.csv`
- `suspicious_sessions.csv`
- `summary_queue.csv`
- `next_actions.csv`
- `summary-stubs/*.md` when `--write-summary-stubs` is enabled
"""
    (outdir / "summary.md").write_text(md, encoding="utf-8")

    summary = {
        "profile": profile,
        "db_path": str(db_path),
        "outdir": str(outdir),
        "days": args.days,
        "sessions": len(session_rows),
        "total_tokens": totals["total_tokens"],
        "api_calls": totals["api_calls"],
        "tool_calls": totals["tool_calls"],
        "top_task": group_rows[0] if group_rows else None,
        "summary_queue_items": len(summary_queue_rows),
        "summary_queue_pending": pending_summary_count,
        "existing_summary_count": existing_summary_count,
        "summary_queue_counts": dict(queue_counts),
        "large_tool_outputs": len(large_tool_rows),
        "large_tool_threshold": args.large_tool_threshold,
        "largest_tool_output": large_tool_rows[0] if large_tool_rows else None,
        "tool_output_patterns": len(tool_output_pattern_rows),
        "top_tool_output_pattern": tool_output_pattern_rows[0] if tool_output_pattern_rows else None,
        "next_actions": next_actions,
        "written_summary_stubs": written_stubs,
        "files": ["summary.md", "sessions.csv", "task_groups.csv", "tools.csv", "skills.csv", "large_tool_outputs.csv", "tool_output_patterns.csv", "suspicious_sessions.csv", "summary_queue.csv", "next_actions.csv"],
    }
    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        print(f"Wrote Hermes usage report: {outdir / 'summary.md'}")
        print(f"Total recorded tokens: {fmt_int(totals['total_tokens'])} over {len(session_rows)} sessions / {fmt_int(totals['api_calls'])} API calls")
        print(f"Summary queue: {len(summary_queue_rows)} items ({pending_summary_count} pending, {existing_summary_count} existing; {', '.join(f'{k}:{v}' for k, v in queue_counts.items()) or 'none'})")
        print(f"Large tool outputs: {len(large_tool_rows)} rows >= {fmt_int(args.large_tool_threshold)} chars")
        print(f"Tool output patterns: {len(tool_output_pattern_rows)} grouped patterns")
        if next_actions:
            first_action = next_actions[0]
            print(f"Next suggested action: {first_action.get('title')} [{first_action.get('kind')}]")
            if first_action.get("command"):
                print(f"Command: {first_action.get('command')}")
        if args.write_summary_stubs:
            print(f"Wrote {len(written_stubs)} summary stubs under {summary_tmp_dir}")
        if group_rows:
            print(f"Top task: {group_rows[0]['root_title']} ({fmt_int(group_rows[0]['total_tokens'])} tokens)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
