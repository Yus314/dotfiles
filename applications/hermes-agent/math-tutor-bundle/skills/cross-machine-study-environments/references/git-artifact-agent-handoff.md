# Git + artifact + agent handoff recipe

## Portable layout

```text
primary machine
├── study repository                 # Git authority
├── proof/code repository            # Git authority
├── bare remotes or hosted remotes
└── document artifacts               # generated/verified authority

secondary machine
├── study checkout (optionally sparse)
├── proof/code checkout
├── machine-local build/cache tree
├── read-only artifact replica
└── machine-local agent profile
```

## Begin/end script behavior

A portable handoff script should detect the host and assign machine-specific roots. Its commands should remain conservative:

```text
status  show Git state and verify the canonical document
begin   require relevant clean scopes; fetch; fast-forward; refresh replica; verify
end     require relevant clean scopes; push existing commits; refresh replica if authority
verify  compare expected and actual canonical document hash
```

It should not commit, merge, rebase, or resolve conflicts.

For a study monorepo, check cleanliness only for the study subtree and shared scripts. For the proof/code repository, check the whole source tree. This allows unrelated study profiles to retain work while keeping mathematics handoffs explicit.

## Secondary Git write smoke test

To prove reverse writes without changing the main branch:

1. Record the secondary checkout's current `HEAD`.
2. Push `HEAD` to a temporary remote branch/ref.
3. Read that ref directly on the authority remote.
4. Compare IDs.
5. Delete the temporary ref.
6. Confirm the ref is gone.

This validates SSH, remote permissions, object transfer, and ref updates more strongly than a dry-run.

## Artifact verification set

At minimum verify:

- canonical PDF/document checksum from checked-in metadata;
- root artifact manifest;
- page-image or OCR manifest;
- search-index checksum;
- SQLite integrity when the index uses SQLite;
- source/version identity embedded in generated metadata.

A matching directory size is not sufficient evidence.

## Formal-project bootstrap

For a clean Lean checkout:

1. install the exact `lean-toolchain` version;
2. fetch project dependency repositories;
3. obtain mathlib caches when available;
4. build the project's imported bridge/base module;
5. compile a known-good exercise;
6. keep `.lake`, `.direnv`, `result*`, and native outputs ignored.

An `unknown module prefix` from a leaf file can mean the imported project module has not yet produced its `.olean`; it is not by itself evidence that the import statement or proof is wrong.

## Hermes launcher verification

Use a host-aware launcher:

```bash
#!/usr/bin/env bash
set -euo pipefail
study_root="...machine-specific absolute path..."
cd "$study_root"
exec hermes -p math "$@"
```

Verification must use the same shell and entry point as the learner:

```text
script executable?
symlink resolves?
launcher directory present in fresh login-shell PATH?
command -v launcher succeeds?
agent terminal-tool pwd equals canonical study root?
```

`hermes config get terminal.cwd` alone is not a CLI workspace test.

## Safe Git integration

When adding declarative host configuration:

- inspect remote divergence before pushing;
- do not force-push if the remote is ahead;
- do not hide unrelated changes with broad stash/reset operations;
- use a clean temporary worktree based on the current remote branch for an isolated fix when needed;
- if system activation needs sudo or interactive approval, complete non-privileged verification and give the learner one exact manual switch command.
