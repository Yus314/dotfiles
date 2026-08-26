---
name: cross-machine-study-environments
description: Use when designing, implementing, repairing, or verifying a study workflow that moves notes, proof/code projects, document artifacts, and an AI tutor profile between multiple machines.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [study, synchronization, git, rsync, multi-machine, reproducibility]
    related_skills: [math-book-study-workflow, grounded-math-document-study]
created_by: agent
---

# Cross-Machine Study Environments

## Purpose

Build multi-machine study workflows around semantic authority rather than placing every directory under one bidirectional file synchronizer. Preserve inspectable learning history, prevent generated/build state from leaking across architectures, and verify the complete handoff path on real machines.

For the detailed implementation and verification recipe, see `references/git-artifact-agent-handoff.md`.
For auditing tutor-knowledge parity and handing architecture review to a control profile, see `references/profile-parity-and-control-plane-handoff.md`.

## Trigger

Use this skill when a learner wants to:

- continue the same book or course on a second computer;
- synchronize Markdown study logs and proof/code projects;
- carry PDF/OCR/search artifacts between machines;
- reproduce Lean or another formal environment on a different OS/architecture;
- run a dedicated Hermes study profile from a portable workspace;
- replace or narrow a broad Syncthing/cloud-drive setup.

## Authority Classification

Classify each path before selecting a transport.

| Data class | Preferred mechanism | Rule |
|---|---|---|
| Notes, proof attempts, review logs | Git | Preserve history and merge intentionally |
| Lean/source code and manifests | Git | Exclude builds and caches |
| PDF/OCR/images/indexes/embeddings | One-way rsync or regeneration | One authority; replicas read-only |
| Build outputs and architecture state | Local rebuild | Never synchronize by default |
| Agent auth/session/memory/cache | Machine-local | Do not file-sync mutable databases or credentials |
| Declarative non-secret config | Dotfiles/Nix | Apply per host |

Do not choose one tool before this classification. A hybrid design is usually simpler and safer than universal bidirectional synchronization.

## Implementation Workflow

1. **Inspect first**
   - Measure data sizes excluding Git/build products.
   - Inspect repository remotes, branches, staged/unstaged changes, and ignore rules.
   - Verify SSH in both directions if machines will push and pull.
   - Identify user changes that must not be overwritten.

2. **Create versioned authorities**
   - Put study records and proof/code source in Git.
   - Use a private hosted remote or an authority-machine bare remote.
   - Deny non-fast-forward pushes where appropriate.
   - A local bare remote is transport, not an independent backup.

3. **Checkpoint existing work deliberately**
   - Commit only intended study paths.
   - Label incomplete proof states as checkpoints rather than pretending they are complete.
   - Never sweep unrelated dirty paths into a setup commit.

4. **Prepare the secondary checkout**
   - Clone from the authority remote.
   - Use sparse checkout when a monorepo contains unrelated study domains.
   - Rebuild ignored dependencies and architecture-specific state locally.

5. **Transfer read-only artifacts**
   - Copy from authority to replica using one-way rsync or regenerate locally.
   - Use deletion mirroring only if the replica is explicitly disposable.
   - Keep source identity and manifests beside derived artifacts.

6. **Configure the AI tutor locally**
   - Keep profile auth, sessions, memory stores, and caches local.
   - Set machine-specific roots through non-secret environment/config values.
   - Use a launcher that enters the canonical study root before starting the profile.

7. **Document the handoff contract**
   - Record remote locations, sparse paths, authority direction, start/end commands, and recovery rules in the study repository.

## Session Handoff Contract

Prefer a one-session/one-host rule:

- **Begin:** require the relevant study scope and source repository to be clean; fetch; fast-forward only; refresh read-only artifacts; verify source identity.
- **Study:** edit on one host; record attempts and confusion normally.
- **End:** inspect differences; commit meaningful checkpoints; push; optionally refresh replicas.

Never auto-commit learner work, auto-resolve proof conflicts, or silently rebase a dirty working tree.

A shared monorepo may contain unrelated dirty work. Scope the preflight clean check to the study subtree and handoff scripts, while still allowing Git to reject a pull when other changes genuinely conflict.

## Verification Requirements

A configuration-only result is insufficient. Verify with real outputs:

- Clone/fetch both repositories on the secondary machine.
- Push a temporary ref from secondary to authority, compare commit IDs, and delete it.
- Compare the canonical document SHA-256 on both machines.
- Compare selected manifests and index checksums.
- Run SQLite `PRAGMA integrity_check` where applicable.
- Install the pinned formal-language toolchain for the secondary architecture.
- Fetch dependency caches, build imported base modules, and compile one known-good proof file.
- Start the tutor through the actual user-facing launcher and have its terminal tool run `pwd`.
- Open a fresh login shell and verify launchers with `command -v`.

## Pitfalls

- **Symlink exists, command missing:** the launcher directory may not be in the actual login shell's `PATH`. Verify target, symlink, and `command -v` separately. Prefer declarative session-path configuration; verify in a new shell.
- **Hermes workspace mismatch:** `terminal.cwd` controls gateway/cron behavior, while CLI uses its launch directory. A CLI launcher must `cd` before `exec hermes -p <profile>`.
- **Unknown Lean module on a clean clone:** build the imported bridge/base module and fetch the project cache before diagnosing the leaf proof as broken.
- **Remote branch is ahead:** fetch and inspect divergence. Never force-push a setup change. Use an isolated worktree or leave the change for explicit integration.
- **Dirty unrelated work:** do not stash, reset, merge, or overwrite it casually. Make targeted commits and isolated changes.
- **Generated content in Git:** do not commit large caches merely to make a second machine work; reproduce or transfer them separately.
- **Mutable databases in sync tools:** profile/session SQLite stores and credentials are machine-local unless the application provides an explicit migration/export mechanism.

## Completion Criteria

The workflow is complete only when both machines can:

1. obtain the same versioned study state;
2. push/pull without non-fast-forward surprises;
3. access a verified copy of required documents/indexes;
4. run one known-good formal/code check locally;
5. launch the tutor in the correct study root;
6. preserve unrelated user work untouched.
