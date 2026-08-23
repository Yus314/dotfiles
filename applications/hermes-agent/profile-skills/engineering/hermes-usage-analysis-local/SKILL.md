---
name: hermes-usage-analysis-local
description: "Profile-local routing and outcome policy adapter for the shared Hermes usage-analysis core."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [hermes, usage, profile-adapter]
    related_skills: [hermes-usage-analysis]
---

# Hermes Usage Analysis — engineering Adapter

Load `hermes-usage-analysis` for the shared procedure, then apply this adapter.

## Routing

- Profile: `engineering`
- Database: `~/.hermes/profiles/engineering/state.db`
- Invoke the analyzer with `--profile engineering`; do not infer the database from the current working directory.
- Treat a reported `db_path` that differs from the path above as a routing failure.
- A default-profile cron or report does not implicitly analyze this profile.

## Local outcome policy

Engineering outcomes: verified working artifacts, reduced defects and maintenance cost, reusable infrastructure, and resolved technical blockers.

Keep control-plane operation, calendar and Org ownership, product-market decisions, and sensitive domain data outside this profile. Distinguish implementation, verification, review, and deployment; a green build is not deployment authority. Prefer the smallest reversible change and verify the real artifact.

Before restarting a heavy implementation session, preserve repository and branch, changed paths, tests, blockers, and the exact next command. Keep generated reports under `~/tmp` unless the user explicitly asks to promote a result.
