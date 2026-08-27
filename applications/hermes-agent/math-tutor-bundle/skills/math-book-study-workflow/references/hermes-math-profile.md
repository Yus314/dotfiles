# Hermes math profile pattern

Use this reference when the user's proof-based mathematics workflow is being separated from the general personal-assistant profile.

## Why separate a math profile

A dedicated Hermes profile is useful when mathematics study has its own long-running state, Socratic dialogue norms, skills, session history, review cadence, and `~/study_log/math` editing boundary. It prevents general secretary memory/session noise from mixing with proof-learning details.

## Recommended shape

- Profile name: `math` unless the user chooses another stable class-level name.
- System of record: keep the shared repository at `~/study_log` and the canonical mathematics root at `~/study_log/math`; do not create a second mathematics log per profile.
- Ownership: the math profile owns deep mathematics dialogue and structural edits to `~/study_log/math`; the default profile may read/summarize and coordinate with calendar/tasks.
- Persona: Socratic proof-based coach; protect productive failure; prefer definitions, examples/non-examples, assumptions/conclusions, hint ladders, proof reconstruction, and understanding-change logs.
- Skills in the initial reviewed allowlist: `math-book-study-workflow`, `grounded-math-document-study`, and `cross-machine-study-environments`. Expand only for an observed workflow need.
- Gateway: do not start with a separate Discord gateway unless the user needs it. First validate CLI/explicit invocation, then decide whether to add a math bot/routing.

## Setup/verification checklist

1. Create or inspect the profile: `hermes profile show math`.
2. Set/verify the model and profile config as needed.
3. Set the intended workspace: `hermes -p math config set terminal.cwd ~/study_log/math`.
4. Update profile-local `SOUL.md` with the Socratic math-study role and `study_log/math` boundaries.
5. Ensure math skills are installed in the math profile; if copying skills manually, copy whole skill directories and verify with `hermes -p math skills list`.
6. Run `hermes -p math doctor --fix` to migrate config.
7. Verify Honcho/memory if used: `hermes -p math honcho enable`, ensure the profile `.env` has required Honcho credentials, then `hermes -p math honcho status` should show connected.
8. Run a small real test: ask the profile to inspect `~/study_log/math` and propose the next small Socratic learning step without editing.

## Pitfalls

- A Hermes profile is not a filesystem sandbox. It separates config, sessions, skills, memory, cron, and gateway state, but local terminal tools still run as the same OS user.
- `terminal.cwd` controls messaging gateway and cron sessions. Hermes CLI sessions intentionally use the directory from which `hermes` was launched, so a CLI-specific study profile should be started from the intended root or through a wrapper that `cd`s there before `exec hermes -p <profile>`. Verify with an actual terminal-tool `pwd`, not only `hermes config get terminal.cwd`.
- If a profile's Honcho status says enabled but not connected, check the profile-local `.env` for `HONCHO_API_KEY` or the configured base URL; default-profile credentials may not be inherited.
- Do not store fine-grained progress in memory. Put per-exercise progress, confusion, weekly plans, and proof drafts in `~/study_log/math`; memory should hold stable learning preferences and system conventions.
