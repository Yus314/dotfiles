---
name: cross-profile-information-exchange
description: "Use when one Hermes profile requests, returns, stores, or integrates information from another profile through semantic memory, compact summaries, or Kanban work orders."
version: 1.2.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [hermes, profiles, handoff, memory, kanban, privacy]
---

# Cross-Profile Information Exchange

## Boundary model

Use four different channels for four different jobs:

1. **Shared semantic memory** carries only stable cross-domain preferences, durable goals/constraints, and environment facts that reduce repeated steering. Isolated profiles such as Food, Finance, and Health do not ingest directly into it; reviewed stable facts use explicit promotion handoffs.
2. **Owner-attested summaries** carry compact current status, conclusions, constraints, uncertainty, and source references without copying domain raw data.
3. **Typed cross-profile handoffs** carry purpose-bound, expiring transfers to named profiles.
4. **Kanban work orders** carry scoped requests and sanitized results for durable cross-profile work.

A Hermes profile is a state and routing boundary, not an operating-system sandbox. Being technically able to read another profile's path does not authorize reading it.

## Routing procedure

1. Identify the source owner profile from the declarative profile registry.
2. State the purpose and the minimum questions that must be answered.
3. Select the narrowest channel:
   - stable and broadly reusable fact → shared semantic memory;
   - current domain status → compact handoff;
   - work requiring execution, retry, or dependencies → Kanban work order.
4. Apply the registry's sensitivity and memory-sharing policy before reading or writing.
5. Return only the requested result and provenance. Do not compensate for a missing handoff by inspecting domain raw data.
6. Treat expired, stale, blocked, degraded, bootstrap, or unreviewed material as unavailable rather than as evidence of no activity.

## Typed handoff envelope

Every new cross-profile handoff uses `cross_profile_handoff` version 2 and must pass `profile-handoff-check` before its body is read.

```yaml
schema_family: cross_profile_handoff
schema_version: 2
handoff_id: food:2026-08-01:stable-preference
source_profile: food
target_profiles: [default]
purpose: stable-preference-promotion
generated_at: 2026-08-01T08:00:00+09:00
valid_until: 2026-08-15T00:00:00+09:00
scope: stable-preference-only
status: ready
source_refs:
  - type: opaque-handle
    value: food-preference-review:2026-08-01
source_health: healthy
sensitivity: ordinary
raw_data_included: false
retention_class: promotable
supersedes: null
assumptions: []
uncertainties: []
```

The body should contain only the sections that are useful:

```markdown
## Conclusions
## Constraints
## Uncertainties
## Requests for the receiving profile
```

`valid_until` is a use deadline, not an automatic deletion time. `transient` packets cannot be promoted to persistent memory; `promotable` packets allow only reviewed stable facts to be promoted; `durable` is reserved for explicit user/audit requirements. Raw data is forbidden for automatic consumption. Source references are opaque handles or credential-free URLs, not raw filesystem paths.

## Consultation requests

Use `profile-consult` for a bounded current-state question when the owner is
known and the local summary is absent or stale. It creates a local request or
response artifact but does not dispatch an agent or read domain data.

```bash
profile-consult request \
  --from default --to finance \
  --scope housing-decision-support \
  --fields status,constraints,confidence,as_of \
  --ttl-hours 24

profile-consult respond REQUEST.md \
  --from finance \
  --field 'status="available"' \
  --field 'confidence="medium"'

profile-consult status
```

The registry permits only the pilot routes and their field allowlists. Requests
are hop 0, responses are hop 1, and `max_hops` is always 1. Never initiate a
profile-to-profile consultation recursively. A response may return only fields
requested by its parent. Structural validation does not prove semantic
sanitization: the owner profile must still ensure values contain no raw domain
data, transcript text, identifiers, credentials, or direct paths.

Use a consultation for a small state lookup. Use Kanban only when the receiver
must execute, retry, track dependencies, or preserve durable completion state.

## Kanban request envelope

```yaml
from_profile: default
to_profile: finance
purpose: Check whether a candidate rent fits the current policy
questions:
  - Is JPY 140000 per month inside the current range?
allowed_sources:
  - finance-owned canonical ledger
return_fields:
  - result
  - recommended_range
  - assumptions
  - uncertainties
forbidden_return:
  - balances
  - individual transactions
expires_at: 2026-08-14T00:00:00+09:00
```

The worker response must state `raw_data_included: false`, identify source-health limitations, and return sanitized conclusions rather than source rows.

## Domain rules

- **Finance:** return budget/range, integrity, freshness, and assumptions; never transactions, balances, account names, or ledger copies.
- **Health:** return compact recovery/load signals and freshness; never raw time series or medical detail.
- **Food:** conversation-derived memory stays in `hermes-food`. Only reviewed stable preferences and constraints may reach general memory through `stable-preference-promotion`; keep meal photos, raw logs, nutrition history, and complete packets domain-local.
- **Study:** share learning preferences and compact next actions; keep line-by-line corrections, attempts, and confusion logs domain-local.
- **Engineering/product:** exchange repository paths, specifications, diffs, tests, blockers, and approval state rather than transcript copies.

## Verification

Before accepting a handoff, check:

- schema family/version and source profile match the registry;
- target profile and purpose are explicitly allowed;
- sensitivity is allowed for the destination;
- `valid_until` and source freshness are current;
- source references are typed opaque handles or credential-free URLs, not raw paths/data;
- `raw_data_included` is false;
- the handoff ID has not already been consumed;
- the receiver stores only the minimum reviewed durable result, not the whole packet.
