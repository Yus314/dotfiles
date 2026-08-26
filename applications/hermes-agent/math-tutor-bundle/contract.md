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
- Topology is first proven with disposable workspace/peer names. Writing a durable smoke fact to the real workspace requires separate approval for the exact fact.

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

1. Candidate review and exact allowlist approval.
2. Disposable Honcho topology test.
3. Separate approval to activate Watari.
4. Watari policy/behavior/canonical lookup canary and independent rollback proof.
5. Separate content-specific approval for one real-workspace durable smoke fact.
6. Lawliet activation only after Watari passes and receives a separate activation approval.

No file in this bundle activates a profile, restarts a gateway, changes cron, installs credentials, or writes Honcho memory.
