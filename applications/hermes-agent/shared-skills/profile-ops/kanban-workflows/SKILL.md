---
name: kanban-workflows
description: "Use when operating Hermes Kanban workflows as an orchestrator or worker: decomposing work, claiming cards, updating status, handoffs, heartbeats, and tenant-safe summaries."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [kanban, orchestration, workers, task-management, hermes]
    related_skills: [personal-assistant-ops, autonomous-ai-agents]
---

# Kanban Workflows

## Overview

This umbrella covers both sides of Hermes Kanban work: the orchestrator that decomposes and routes work, and the worker that claims cards, executes safely, and reports back. Use one skill with role-labeled subsections instead of separate role micro-skills.

## When to Use

- A user or profile asks to run a persistent multi-card workflow.
- You are deciding whether to use the board or do work directly.
- You are acting as a worker and need lifecycle, heartbeat, or summary conventions.
- A Kanban workflow is stuck, duplicated, cross-tenant, or under-specified.

## Orchestrator Role

1. Understand the goal, constraints, deliverables, and user-visible success criteria.
2. Sketch the task graph before creating cards: dependencies, independent leaves, verification, and integration.
3. Create cards with clear acceptance criteria and enough context that a worker does not need the originating chat.
4. Do not steal worker tasks unless explicitly assigned. The orchestrator's job is decomposition, sequencing, and final integration.
5. Report back with board state, completed handles, blockers, and the next required human decision.

## Worker Role

1. Claim only cards you can actually execute in this environment/profile.
2. Read the full card, linked artifacts, and tenant/profile context before acting.
3. Send heartbeats when a task is long-running or blocked, not for every trivial step.
4. Use block reasons that can be answered quickly: missing credential, ambiguous target, failing command + exact output.
5. Final summaries should include what changed, where, verification output, and residual risks.

## Board vs Direct Work

Use the board for durable, parallel, or cross-profile work. Do direct tool work for small single-session tasks where board overhead would hide rather than clarify progress.

Do not treat Kanban as a synonym for synchronous `delegate_task`. Use synchronous
delegation when no durable state, retry, dispatcher, or cross-session handoff is
needed.

## Recovery and Notification

1. **Stale card:** inspect the last heartbeat and output, then explicitly retry,
   split, reassign, block, or cancel it. Do not silently create a duplicate.
2. **Vague blocker:** request only the minimum missing credential, path, decision,
   or acceptance criterion.
3. **Long-running work:** retain a process/session handle and bounded verification
   evidence; a green process alone does not prove completion.
4. **Wrong tenant/profile:** stop and reroute instead of patching another profile's
   state.
5. **Completion routing:** confirm where the result will be delivered. A completed
   card whose artifact or notification cannot be found is not operationally done.

## Common Commands and Tools

- CLI: `hermes kanban init/create/list/show/assign/link/comment/complete/block/unblock/archive/tail`.
- Worker tools commonly include `kanban_show`, `kanban_comment`,
  `kanban_heartbeat`, `kanban_complete`, and `kanban_block`.
- Confirm the board and task IDs before mutations; do not infer them from another
  profile's current chat.

## Tenant, board, and workspace safety

- Hermes profiles separate agent state but are **not** a Kanban privacy boundary.
  A shared board's task bodies, comments, paths, events, and handoffs are durable
  cross-profile data; tenant labels are routing metadata, not hard isolation.
- Put only redacted work orders and owner-attested compact summaries on the
  integration board. Never copy ledger transactions/balances, raw health
  streams, meal records, credentials, or sensitive attachment paths into it.
- If a task genuinely requires sensitive raw data, use a separate domain-owned
  board and return only a sanitized result to the integration board.
- Never assume a worker has the same current directory, credentials, memory, or
  tool state as the orchestrator.
- Pass explicit paths only when every profile allowed to read the board may also
  know that path; otherwise use a domain-local handle and sanitized handoff.

## Common Pitfalls

1. **Doing the work while pretending to orchestrate.** Split and delegate if the board is being used.
2. **Vague cards.** A card titled "fix bug" without repro, files, expected output, and verification is not actionable.
3. **Claiming your own generated card accidentally.** Verify role and ownership before status changes.
4. **Silent long-running work.** Heartbeat with meaningful progress or blockers.
5. **Cross-tenant leakage.** Do not mention or use artifacts from another user's/profile's board unless explicitly shared.

## Verification Checklist

- [ ] Every card has clear owner/status/acceptance criteria.
- [ ] Dependencies and blockers are explicit.
- [ ] Worker summaries include real verification output.
- [ ] Orchestrator final response reconciles all cards and user-facing deliverables.
- [ ] Stuck-card recovery leaves a visible decision trail without duplicate work.
- [ ] Completion artifacts and notifications reach the intended destination.
