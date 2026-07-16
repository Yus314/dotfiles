---
name: hermes-usage-analysis
description: Analyze local Hermes state.db usage, context pressure, tool-output bloat, and restart opportunities without confusing local accounting with official provider quota.
version: 2.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [hermes, usage, tokens, context, diagnostics, sqlite]
---

# Hermes Usage Analysis

## Scope

Use this skill to diagnose recorded Hermes usage, heavy task groups, API-call
pressure, repeated skill loading, oversized tool output, and work that should
move to a fresh session. The data comes from a local profile's `state.db`; it is
**not** official OpenAI/Codex quota, billing, or remaining allowance.

Do not dump raw messages or large CSV/log bodies into the model context. Run the
deterministic analyzer, retain full artifacts locally, and inspect compact
aggregates or narrowly selected rows.

## Select the Accounting Source Explicitly

The stable analyzer path is:

```bash
python ~/.local/share/hermes/shared-skills/usage-ops/hermes-usage-analysis/scripts/hermes_usage_analyzer.py \
  --profile PROFILE --days 7 --outdir /tmp/hermes-usage-PROFILE --json
```

`PROFILE` may be `default` or a named Hermes profile. `--profile career`, for
example, resolves `~/.hermes/profiles/career/state.db`. Never assume a command
run inside a named profile automatically reads that profile's database.

Use `--db /explicit/path/state.db` only for fixtures or an intentionally custom
database. `--db` and `--profile` are mutually exclusive. The JSON result reports
both `profile` and `db_path`; verify them before interpreting totals.

## Analysis Workflow

1. **Define the question.** Quota pressure, one heavy task, tool-output bloat,
   repeated retries, skill-loading cost, or restart timing require different
   evidence.
2. **Confirm profile and time window.** Start with 1–7 days; widen only when the
   smaller window cannot answer the question.
3. **Run to a dedicated output directory.** Keep raw tables out of synced notes
   and out of chat context.
4. **Read `summary.md` and JSON first.** Inspect individual CSVs only for a
   specific follow-up.
5. **Separate drivers.** Distinguish visible prompt/context, tool results,
   retries/API calls, subagents, and generated output.
6. **Choose one reversible mitigation.** Narrow tool output, split context,
   improve a handoff, cap an evaluation, or stop low-value automation.
7. **Verify outcome.** A green cron or smaller token count is not sufficient;
   confirm reduced restart/decision cost or improved task completion.

## Interpretation Guardrails

- High token volume can be justified by a valuable research or implementation
  result; low token volume can still represent wasted retries.
- Local token accounting and provider quota dashboards answer different
  questions.
- Do not impose a universal meta-work percentage or token ceiling. Treat
  thresholds as review triggers, not automatic stop rules.
- Do not automatically promote generated summaries into curated PIM, org, diary,
  or reporting artifacts.
- Never expose raw message bodies, user identifiers, chat IDs, or credentials in
  a report or final response.

## Context Actions

- Use `/compress` when the same task and evidence still matter but verbose history
  can be summarized.
- Use `/new` when the objective, work phase, repository, or domain changes.
- Before `/new`, preserve only durable state: goal, decisions, verified facts,
  changed paths, tests, blockers, and the exact next command.
- Prefer compact structured handoffs over reloading full transcripts.

See:

- [`references/diagnostics-and-interpretation.md`](references/diagnostics-and-interpretation.md)
- [`references/context-hygiene-and-restart-handoffs.md`](references/context-hygiene-and-restart-handoffs.md)

If `hermes-usage-analysis-local` is available, load it for the selected profile's
DB path, review ownership, and domain-specific policy.
