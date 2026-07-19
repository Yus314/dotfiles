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

# Hermes Usage Analysis — english Adapter

Load `hermes-usage-analysis` for the shared procedure, then apply this adapter.

## Routing

- Profile: `english`
- Database: `~/.hermes/profiles/english/state.db`
- Invoke the analyzer with `--profile english`; do not infer the database from the current working directory.
- Treat a reported `db_path` that differs from the path above as a routing failure.
- A default-profile cron or report does not implicitly analyze this profile.

## Local outcome policy

English outcomes: completed TOEIC practice, corrected recurring errors, retained vocabulary/grammar, and measurable score progress.

For Japanese/English prompt comparisons, separate visible token cost, response quality, learning value, and task completion. Do not force English-only prompting from a single shorter sample; require reproducible comparisons.

Keep generated reports under `~/tmp` unless the user explicitly asks to promote a result. Do not create curated notes, diary entries, weekly reports, or domain records automatically. Process health and token reduction are supporting signals, not outcomes by themselves.
