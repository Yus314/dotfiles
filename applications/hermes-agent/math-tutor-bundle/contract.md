# Math tutor parity contract (schema 1)

## Goal

Lawliet and Watari provide equivalent mathematics tutoring policy and user-centered semantic continuity without synchronizing mutable Hermes state. Parity means matching canonical content and static policy plus an explicitly tested Honcho identity topology; it does not mean equal session, message, cache, or installed-skill counts.

## Authorities

1. `study_log` and Lean source are Git-authoritative. Each study session follows fetch/fast-forward, one active writer for the scoped work, reviewed commit, and push.
2. Lawliet is the sole authority for generated LADR artifacts under the configured artifact root. Watari receives the existing one-way replica or regenerates only where a separate source explicitly permits it; it is never promoted to a second writer by this bundle.
3. This directory in the dotfiles repository is authoritative for `SOUL.md`, the allowlisted skill packages, non-secret profile fragments, host overlays, and bundle digests.
4. Canonical files and this static tutor policy outrank Honcho conclusions, representations, and inferred semantic memory. A conflict is surfaced and corrected explicitly; semantic memory never rewrites canonical files automatically.

## Honcho topology

- Workspace: `hermes-math`
- Shared user peer: `kaki-math`
- Lawliet AI peer: `math-lawliet`
- Watari AI peer: `math-watari`
- The user peer is intentionally shared. The AI peer is intentionally host-specific for provenance and independent rollback.
- The disposable test proved that user-self conclusions are shared and AI self-scopes are distinct, but a Lawliet-AI conclusion about the user is not visible in the Watari-AI observer scope. Therefore these identifiers alone do not yet deliver inferred semantic continuity under the default `ai.observeOthers = true` behavior.
- Activation is blocked until a separately approved design selects user-self conclusion scope, a shared AI observer, or an explicit reviewed promotion/replication route. Writing a durable smoke fact to the real workspace still requires separate approval for the exact fact.

## Included static inputs

- `SOUL.md`
- `config-fragment.json`
- `skills/<allowlisted-package>/**`
- exactly one declared host overlay
- generated `honcho.json`, `candidate-metadata.json`, and `sync-inputs.json`

## Exclusions and forbidden synchronization inputs

Never synchronize or bundle live Hermes state: `state.db`, `state.db-wal`, `state.db-shm`, `sessions`, `logs`, `cache`/`caches`, `auth.json`, `.env`, credentials, OAuth data, `cron`, gateway state, process files, or lock files. Build outputs, architecture-specific Lean state, and generated package caches remain local. Secrets are injected locally and reported only as `present` or `missing`; no value or hash may enter a candidate or report.

## Retention and rollback

Changing future routing does not migrate, delete, or rewrite prior Honcho data. On an affected host, rollback static policy to the prior declarative generation and stop new Honcho writes or disable Honcho. Continue from canonical files and host-local sessions. Investigate contradictions with provenance; do not automatically delete semantic history.

## Rollout gates

1. Candidate review and exact allowlist approval (complete).
2. Disposable Honcho topology test and cleanup (executed; observer-scope parity failed, so activation remains blocked).
3. Separate design approval resolving cross-host user-conclusion visibility.
4. Separate approval to activate Watari.
5. Watari policy/behavior/canonical lookup canary and independent rollback proof.
6. Separate content-specific approval for one real-workspace durable smoke fact.
7. Lawliet activation only after Watari passes and receives a separate activation approval.

No file in this bundle activates a profile, restarts a gateway, changes cron, installs credentials, or writes Honcho memory.
