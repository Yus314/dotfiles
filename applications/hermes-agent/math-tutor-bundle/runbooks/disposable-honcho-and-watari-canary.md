# Prepared-only Honcho topology test and Watari canary

STATUS: PREPARED; DO NOT RUN FROM THIS CANDIDATE TASK.

## Preconditions

- Candidate digests reviewed and minimal allowlist approved.
- `HONCHO_API_KEY` is installed through each host's profile-local secret mechanism; checks print only `present`/`missing`.
- No real workspace/user/AI peer names are reused in the disposable test.
- Watari activation has separate explicit approval.

## Disposable topology test

Generate a random test suffix locally. Use workspace `hermes-math-disposable-<suffix>`, shared user peer `kaki-math-disposable-<suffix>`, and AI peers `math-lawliet-disposable-<suffix>` / `math-watari-disposable-<suffix>`.

1. Create two disposable profile roots outside every real `HERMES_HOME` and study repository.
2. Materialize the same candidate bundle into both, changing only the disposable workspace/user/AI peer identifiers in temporary untracked config.
3. Through Lawliet, write one benign exact token as the disposable user peer.
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

## Actions still requiring user approval

- Exact three-skill allowlist.
- Disposable external Honcho writes and cleanup (even though isolated).
- Watari activation/restart and canary.
- Exact real-workspace durable smoke fact.
- Lawliet activation/restart.
