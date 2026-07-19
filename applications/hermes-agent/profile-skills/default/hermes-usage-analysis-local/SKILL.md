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

# Hermes Usage Analysis — default Adapter

Load `hermes-usage-analysis` for the shared procedure, then apply this adapter.

## Routing

- Profile: `default`
- Database: `~/.hermes/state.db`
- Invoke the analyzer with `--profile default`; do not infer the database from the current working directory.
- Treat a reported `db_path` that differs from the path above as a routing failure.
- A successful weekly or monthly review proves process health only; verify that it prevented a miss, reduced restart or decision cost, or advanced a user-facing outcome.

## Local outcome policy

General assistant outcomes: prevented misses, reduced restart/decision cost, and useful actions actually advanced.

Separate cross-domain assistant effectiveness from raw token minimization. Review task concentration, source/tool-output shares, retries, and whether infrastructure work produced a verified net benefit. Use the smallest reversible operational change and retire recurring reviews whose burden exceeds demonstrated value.

Keep generated reports under `~/tmp` unless the user explicitly asks to promote a result. Do not create curated notes, diary entries, weekly reports, or domain records automatically. Process health and token reduction are supporting signals, not outcomes by themselves.
