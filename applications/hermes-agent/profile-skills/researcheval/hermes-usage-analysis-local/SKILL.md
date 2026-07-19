---
name: hermes-usage-analysis-local
description: "Profile-local routing and outcome policy adapter for the shared Hermes usage-analysis core."
version: 1.1.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [hermes, usage, profile-adapter]
    related_skills: [hermes-usage-analysis]
---

# Hermes Usage Analysis — researcheval Adapter

Load `hermes-usage-analysis` for the shared procedure, then apply this adapter.

## Routing

- Profile: `researcheval`
- Database: `~/.hermes/profiles/researcheval/state.db`
- Invoke the analyzer with `--profile researcheval`; do not infer the database from the current working directory.
- Treat a reported `db_path` that differs from the path above as a routing failure.
- A default-profile cron or report does not implicitly analyze this profile.

## Local outcome policy

Research-evaluation outcomes: reproducible evidence, citation/tool-trace quality, resolved uncertainties, and reusable evaluation artifacts.

Keep token and tool-call caps distinct from quality, citation, reproducibility, and privacy verdicts. A cap failure is not automatically a quality failure; a rate limit, crash, or missing final answer is not evidence of a privacy pass. Document the source of each metric when public benchmark accounting and private canary accounting differ.

Keep raw evaluation traces and canaries outside shared skills, and compact them before model inspection.

Keep generated reports under `~/tmp` unless the user explicitly asks to promote a result. Do not create curated notes, diary entries, weekly reports, or domain records automatically. Process health and token reduction are supporting signals, not outcomes by themselves.
