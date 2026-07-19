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

# Hermes Usage Analysis — career Adapter

Load `hermes-usage-analysis` for the shared procedure, then apply this adapter.

## Routing

- Profile: `career`
- Database: `~/.hermes/profiles/career/state.db`
- Invoke the analyzer with `--profile career`; do not infer the database from the current working directory.
- Treat a reported `db_path` that differs from the path above as a routing failure.
- A default-profile cron or report does not implicitly analyze this profile.

## Local outcome policy

Career outcomes: clearer decisions, stronger applications/interviews, completed work, and reduced restart cost.

Distinguish career work—reflection, applications, technical growth, and workplace decisions—from Hermes meta-work. Do not treat a high-cost session as waste when it creates a verified artifact or resolves an important decision.

Keep generated reports under `~/tmp` unless the user explicitly asks to promote a result. Do not create curated notes, diary entries, weekly reports, or domain records automatically. Process health and token reduction are supporting signals, not outcomes by themselves.
