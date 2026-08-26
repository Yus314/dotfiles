# Tutor profile parity and control-plane handoff

Use this procedure when two machines can read the same study files but may not have equivalent AI-tutor knowledge or behavior.

## Audit three independent layers

1. **Canonical learning state**
   - Compare Git commit IDs for study logs and proof/code repositories.
   - Compare pinned document and selected artifact hashes.
   - Matching files mean the tutor can reconstruct the same explicit study state; they do not prove equal memory or behavior.

2. **Static tutor behavior**
   - Compare model/provider, `SOUL.md` identity/hash, enabled study skills, and non-secret profile config.
   - Count alone is insufficient: verify the required allowlisted skills by name.
   - Prefer a declarative, versioned static bundle. Keep machine-specific roots in local non-secret config.

3. **Dynamic continuity**
   - Inspect the configured memory provider and its live availability, workspace, AI/user peer identities, and session strategy.
   - Compare local session statistics only to explain continuity differences; local session counts are not a parity target.
   - Never sync live session SQLite, logs, caches, OAuth files, or credential stores.

Report parity per layer rather than answering a single yes/no. A typical safe target is equal canonical state + equal static tutor policy + intentionally selected semantic-memory sharing, while keeping runtime state local.

## Semantic-memory design decision

Explicitly choose between:

- **One shared AI identity:** strongest cross-host continuity; also couples observations and concurrent writes.
- **Host-specific AI identities with a shared user representation:** clearer provenance and safer host separation; less automatic tutor-specific continuity.
- **No shared semantic memory:** simplest isolation; continuity must be reconstructed from canonical notes and compact handoffs.

Do not copy an API key in a handoff or repository. Configure credentials locally through the approved secret mechanism, then verify provider status without printing the secret.

## Handoff to the control/main profile

When architecture review or implementation planning belongs to the control profile:

1. Create a minimal `cross_profile_handoff` version 2 envelope.
2. Use `purpose: review-request`, `sensitivity: ordinary`, `raw_data_included: false`, and a short validity window.
3. For `review-request`, include `requested_fields`, `response_deadline`, `hop_count: 0`, and `max_hops: 1`; otherwise the fail-closed validator rejects it.
4. Use opaque source handles in the envelope—not credentials, raw transcripts, or domain-owned paths/data.
5. Validate before consumption with `profile-handoff-check --target <profile> --registry <registry>`.
6. If the receiver must actually reason, retry, or return a durable result, create a Kanban work order assigned to the control profile and attach the validated handoff.
7. Verify the task is `ready`, run one dispatcher pass when immediate execution is requested, and verify it becomes `running` with a concrete run ID.

The work order should request a recommendation, trade-offs, implementation plan, risks, and verification. It should forbid credentials, session transcripts, and raw learner attempts, and should state whether changes are advisory-only pending user approval.

## Verification checklist

- Canonical Git and document identities match.
- Required static tutor files and skill names match.
- Memory provider status is live on both hosts, or the intentional difference is documented.
- AI/user peer and session strategy are explicitly chosen, not inherited accidentally.
- Sessions/auth/runtime state remain host-local.
- Typed handoff passes the validator.
- Control-profile task has an ID, attachment, assignee, status, and run record.
