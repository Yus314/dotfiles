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

# Hermes Usage Analysis — indiedev Adapter

Load `hermes-usage-analysis` for the shared procedure, then apply this adapter.

## Routing

- Profile: `indiedev`
- Database: `~/.hermes/profiles/indiedev/state.db`
- Invoke the analyzer with `--profile indiedev`; do not infer the database from the current working directory.
- Treat a reported `db_path` that differs from the path above as a routing failure.
- A default-profile cron or report does not implicitly analyze this profile.

## Local outcome policy

Indie-development outcomes: shipped artifacts, validated product decisions, resolved blockers, and reduced iteration cost.

Distinguish product discovery, research, implementation, tests, and shipped artifacts from Hermes meta-work. Apply an ROI gate to infrastructure changes: smallest reversible change, real execution, measurable benefit, and rollback when the gain is unproven. Do not turn a heuristic meta-work share into a hard quota.

Before restarting a heavy implementation session, preserve branch/path, changed files, test output, artifact handles, blockers, and the exact next command.

Keep generated reports under `~/tmp` unless the user explicitly asks to promote a result. Do not create curated notes, diary entries, weekly reports, or domain records automatically. Process health and token reduction are supporting signals, not outcomes by themselves.
