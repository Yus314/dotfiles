# Disposable Honcho topology result and Watari canary

STATUS: USER-SELF CONTINUITY APPROVED; CREDENTIAL PRESENCE-GATED; WATARI CANARY NOT APPROVED.

The approved disposable test was executed on 2026-08-26 with benign random
identifiers only. Its authoritative report is
`artifacts/disposable-honcho-topology-report.json` in the Kanban workspace.
All five conclusions were deleted and the disposable workspace was deleted.
No canonical file digest changed.

The test found an important topology constraint: a conclusion created by the
Lawliet AI observer about the shared user peer is not listed in the Watari AI
observer's conclusion scope. A user-self conclusion is shared, and the two AI
self-scopes remain correctly distinct. The approved design therefore sets
`ai.observeOthers = false`: explicit durable goals/preferences written for
`peer=user` resolve to the shared user-self scope, while host-specific AI
observations remain local to `math-lawliet` or `math-watari`. Promotion of an AI
inference to user-self requires explicit review; it is never automatic.

## Preconditions

- Candidate digests reviewed and minimal allowlist approved.
- `HONCHO_API_KEY` is installed from `applications/hermes-agent/secrets.yaml` through each host's profile-local sops-nix secret path; checks print only `present`/`missing`.
- No real workspace/user/AI peer names are reused in the disposable test.
- Watari activation has separate explicit approval.

## Disposable topology test

Generate a random test suffix locally. Use workspace `hermes-math-disposable-<suffix>`, shared user peer `kaki-math-disposable-<suffix>`, and AI peers `math-lawliet-disposable-<suffix>` / `math-watari-disposable-<suffix>`.

1. Create two disposable profile roots outside every real `HERMES_HOME` and study repository.
2. Materialize the same candidate bundle into both, changing only the disposable workspace/user/AI peer identifiers in temporary untracked config.
3. Through Lawliet, write one benign exact token as the disposable user peer's self-conclusion.
4. Through Watari, retrieve the exact token using the provider's authoritative conclusion/list API, not semantic similarity alone.
5. Through each AI peer, create distinct benign attribution tokens; list them and verify host attribution is distinct.
6. Create a synthetic contradiction from one AI peer; verify attribution and verify no canonical Git file changed.
7. Delete disposable conclusions by retained provider IDs, verify authoritative absence, then remove the disposable workspace if the provider supports it.
8. Record commands, exit codes, provider object IDs only where safe, and cleanup evidence. Never print the API key.

## Watari canary after separate approval

1. Fetch the reviewed dotfiles candidate revision into an isolated clean worktree on Watari.
2. Build the Watari Home Manager/darwin candidate without switching; inspect generated `SOUL.md`, config fragment, skill source paths, and `honcho.json` digests.
3. Run `drift_check.py` with `--probe-live` on Watari. Resolve every undeclared overlay difference and forbidden sync-path finding.
4. Confirm gateway idle/drained. Activate only the reviewed Watari generation; leave Lawliet untouched.
5. Start a fresh math CLI session in `/Users/kaki/study_log/math`; have its terminal tool report `pwd`.
6. Run all cases in `behavior-fixture.json`. Record policy conformance separately from model availability.
7. Verify canonical Git lookup, allowlisted skill resolution/source, expected model/provider, expected shared user-peer fingerprint, and AI peer `math-watari`.
8. Exercise rollback to the previous Watari generation and confirm Lawliet and remote memory history are unchanged. If Honcho is problematic, disable new writes/disable Honcho rather than deleting conclusions.

## Later real-workspace smoke (separate content approval)

Ask the user to approve the exact ordinary durable math preference or goal to write. Do not use an exercise attempt, confusion transcript, or temporary progress. Write through one host, retrieve through the other, retain evidence, and do not auto-delete unless deletion was part of the approval.

## Value-hidden credential migration

Run from the repository root on Lawliet. The migration script first checks the existing SOPS `env` field in memory, then falls back to the existing regular Lawliet `~/.hermes/.env` source when that field has no Honcho entry. It extracts the already-used value without printing it and feeds a JSON string to `sops set --value-stdin`. It creates no plaintext temporary file and reports presence only:

```sh
python applications/hermes-agent/scripts/migrate_math_honcho_secret.py
```

Then build both hosts without switching. Activation decrypts the dedicated `math_honcho_env` field to `~/.hermes/profiles/math/.env` with mode 0400. Do not compare values with hashes, suffixes, shell arguments, or diagnostic output.

## Actions still requiring user approval

- Watari activation/restart and canary.
- Exact real-workspace durable smoke fact.
- Lawliet activation/restart.
