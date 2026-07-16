# Context Hygiene and Restart Handoffs

## Compress versus restart

Choose compression when the objective and evidence set are unchanged and the main
problem is verbose history. Choose a new session when the task changes phase,
repository, domain, or decision frame, or when old context now causes incorrect
assumptions.

## Minimal restart handoff

```markdown
# Restart handoff
- Goal:
- Current phase:
- Verified facts:
- Decisions and reasons:
- Changed artifacts:
- Tests and real outputs:
- Blockers/risks:
- Exact next action:
- Explicitly excluded stale context:
```

Keep it factual and compact. Do not copy secrets, raw conversation streams, or
value-laden personal conclusions into an operational handoff.

## Heavy-task handoff

For expensive work, preserve a verifiable handle rather than narrative alone:
absolute path, branch, commit, test command/result, generated artifact, URL/ID, or
process/session handle. If work produced no durable artifact and did not advance a
user outcome, record that plainly and reconsider repeating it.
