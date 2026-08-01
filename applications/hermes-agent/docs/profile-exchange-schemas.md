# Profile exchange schema families

This document defines the machine-checked metadata contracts for local Hermes
profile exchange. The declarative policy of record remains
`../profile-registry.json`; the executable validators live in
`../scripts/profile_exchange_schema.py`.

## Boundary model

- `weekly_summary_v1` is an owner-attested domain snapshot.
- `cross_profile_handoff_v2` is a purpose-bound transfer to named consumers.
- They are separate schema families. Only routing/security concepts are shared.
- Validation proves metadata shape and policy compatibility, not narrative truth.
- Artifact bodies and referenced sources are not read until metadata validation
  succeeds.

## `weekly_summary_v1`

Required frontmatter:

```yaml
schema_family: weekly_summary
schema_version: 1
owner_profile: english
generated_at: 2026-07-16T20:00:00+09:00
coverage_start: 2026-07-13
coverage_end: 2026-07-19
source_watermark: review:2026-W29
status: domain-owned
```

The coverage range must contain the complete expected ISO week. The current
summary checker retains legacy heading/marker support during migration, but any
artifact that declares `schema_family` is validated strictly as
`weekly_summary_v1`.

## `cross_profile_handoff_v2`

Required frontmatter:

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

### Source references

Automatic handoffs use structured references. `opaque-handle` and
`local-handle` values are identifiers, not filesystem paths. `url` references
must be HTTP(S) URLs without embedded credentials. The consumer gate never
opens a reference.

### Validity versus retention

- `valid_until` controls whether the packet may be used for a new decision.
- `transient` forbids promotion into persistent semantic memory.
- `promotable` permits a receiving profile to promote only a reviewed stable
  fact, not the packet or raw source.
- `durable` is reserved for an explicit user/audit requirement.

Expiry does not delete an artifact. Invalid or expired packets remain untouched
and are simply unavailable to automatic consumers.

### Replay

`handoff_id` is the idempotency key. `profile-handoff-check --seen-ids FILE`
accepts either a JSON list of consumed IDs or
`{"consumed_ids": [...]}` and rejects a replay. The checker is read-only;
the consumer is responsible for atomically recording a successful consumption.
`supersedes` may name an older handoff but may not equal the current ID.

## Consultation request/response

Use `profile-consult` for bounded current-state questions. It creates local
0600 artifacts only; it does not dispatch agents, inspect domain sources, or
promote memory.

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

A `review-request` requires `requested_fields`, `response_deadline`,
`hop_count: 0`, and `max_hops: 1`. A `consultation-response` requires
`in_reply_to`, `returned_fields`, `hop_count: 1`, and `max_hops: 1`.
Responses may return only fields named by the request. Registry routes bound
source, destination, fields, and maximum TTL. `supersedes` remains replacement
semantics and is not used for reply correlation.

The initial pilot routes are `default→finance`, `default→career`,
`default→economics`, and `math→economics`. Domain owners remain responsible for
the semantic truth and sanitization of response values; structural validation
cannot prove that a value contains no sensitive narrative.

## Consumer gate

Run:

```bash
profile-handoff-check HANDOFF.md \
  --target default \
  --registry ~/.local/share/hermes/profile-registry.json \
  --seen-ids ~/.local/state/hermes/profile-handoffs/consumed.json
```

Exit 0 returns compact validated metadata and the artifact path. Exit 1 returns
reason codes only. Rejected body text is never echoed. A consumer may read the
body only after exit 0.

The checker rejects unsupported versions, unknown fields, missing/wrong
recipients, unknown profiles or purposes, timezone-less or expired validity,
future generation time beyond a small clock-skew allowance, disallowed
sensitivity, raw-data flags, invalid retention, path-like source references,
replays, and self-supersession.

## Food promotion

Food conversation-derived memory lives in `hermes-food`. General shared memory
receives food information only through a valid ordinary-sensitivity
`stable-preference-promotion` handoff followed by review. Meal photos, meal-log
text, nutrition history, and the complete handoff are not promoted.
