# Math tutor parity candidate contract (schema 2)

## Scope and non-claim

This directory builds review-only Lawliet and Watari math-profile candidates. It does not activate a profile, switch a Nix generation, restart/create a gateway, install credentials, write Honcho memory, or claim behavioral parity from static files. A fresh-session model canary and qualified manual mathematical review remain separate approval gates.

Parity means the same frozen synthetic learner state stays in the same permitted hint band and follows the same evidence/privacy rules. It does not mean equal prose, session/message/cache counts, built-in skill totals, or copied host state.

## F1 — portable policy and exact approved skill plane

- `SOUL.md` is host-neutral and uses `~/study_log/math`; effective candidate policy must contain neither `/home/kaki` nor `/Users/kaki`.
- R1–R12 are explicit invariants in SOUL. Detailed procedure remains in three complete packages:
  1. `math-book-study-workflow`
  2. `grounded-math-document-study`
  3. `cross-machine-study-environments`
- `refresh_manifest.py` hashes every package file into `package_sha256`. Candidate drift checks fail closed on an extra/missing package, any package-byte change, directory/frontmatter mismatch, normalized slash/Discord command collision, probable secret material, or forbidden live state.
- This bundle-local, digest-pinned `skills/study` tree is the single approved parity supply path. Built-ins and preserved unmanaged roots are outside the explicit parity claim and must not shadow/collide with the three names.

## F2 — registry, runtime, plugin, and drift identity

- `profile-registry.json.profiles.math.parity_candidate` is the declarative candidate contract for role-adjacent identity, canonical root, summary boundary, exact skill packages, candidate Honcho workspace, presence-gated semantic readiness, continuity scope, Hermes revision, and enabled math-profile plugins.

`runtime-identity.json` records the reviewed Hermes v0.19.0 composition and the sorted enabled plugin set. The math candidate enables no profile plugin; packaged default-only plugins, including natural-OK shadow behavior, are not attributed to math. `drift_check.py` reports independent dimensions for:

- canonical repository readiness;
- static policy/content;
- exact skill provenance;
- runtime revision and plugin set;
- registry/candidate consistency;
- semantic-memory readiness;
- behavior-harness readiness.

A green static dimension is not activation or runtime behavior evidence. Secret readiness is reported only as `present`/`missing`; values and hashes never enter reports.

## F3 — bounded fixture-only materializer

`math_profile_materialize.py` consumes an immutable candidate and refuses destinations below the running user's real `~/.hermes`. Its only supported target is an isolated fixture profile containing a regular `.math-parity-fixture` marker; dry-run performs no filesystem mutation.

It may update only:

- `config.yaml`: `model.default`, `model.provider`, `terminal.cwd`, approved `memory` keys, and the managed parity skill external-dir entry;
- `SOUL.md`;
- `honcho.json` with non-secret identity and observation policy;
- `.parity/candidate-metadata.json`;
- `skills/parity-study/**` (the materializer-owned exact package tree).

All unrelated config keys, plugins, model fallbacks, unmanaged external skill roots, and unrelated files survive. The script never materializes credentials, `.env`, databases, sessions, caches, cron, gateway/process state, auth, or lock files. Dry-run emits path/action/digest/mode only. Apply uses atomic file replacement, mode 0600 for `config.yaml` and `honcho.json`, and is byte-idempotent.

`default.nix` is build-only. For either `host="lawliet"` or `host="watari"`, it builds the immutable candidate, executes the behavior-harness self-test, executes a dry-run materialization into `$TMPDIR`, and exports the candidate, redacted plan, and tools. It has no Home Manager activation wiring.

## F4 — frozen synthetic behavior gate

`behavior-fixture.json` freezes A1–A18, including every P0 case (A1–A5, A7–A15, A17), P1 cases (A6, A16, A18), answer-key decisive bridges, acceptable pre-bridge hints, decisive/privacy forbidden terms, expected fixture-relative writes, target surfaces, and the 0–2 manual rubric.

`run_behavior_parity.py --self-test` exercises one deliberate pass and one deliberate forbidden-term failure oracle for every scenario. This proves only that the harness distinguishes its synthetic pass/fail records; its report says `behavioral_compliance_claim: not-run`.

A later real parity run must use fresh sessions, an isolated study root, frozen model/provider settings, at least three runs per host, and result records containing host, candidate digest, model/provider, surface, scenario, run index, tool traces, fixture-relative writes, and manual-review state. Any P0 leak blocks acceptance. Automatic checks do not replace mathematical review.

## Authorities and forbidden state

1. `study_log` and Lean source remain Git-authoritative with fetch/fast-forward and one active writer for scoped updates.
2. Lawliet remains sole authority for configured generated LADR artifacts; Watari is a one-way replica or separately approved regenerator.
3. This bundle and the math parity registry entry are the static candidate authorities.
4. Canonical files outrank semantic-memory conclusions; contradictions are surfaced, never auto-overwritten.

Never bundle or synchronize: `state.db*`, sessions, logs, caches, auth, `.env`, credentials, OAuth, cron, gateway/process state, lock files, architecture-specific Lean build state, or raw learner attempts.

## Honcho continuity and credential gate

The candidate workspace is `hermes-math`, with shared user peer `kaki-math` and host-specific AI peers `math-lawliet` and `math-watari`. The approved continuity model writes stable cross-host learning goals/preferences as user-self conclusions. `ai.observeOthers=false` makes explicit `peer=user` conclusions resolve to the shared user's self-scope, while AI self-observation remains attributable to each host-specific AI peer. Observer-scoped AI inference is host-local and is never silently replicated or promoted.

Semantic memory is `approved-presence-gated`: configuration may be materialized, but actual readiness is `ready` only when `HONCHO_API_KEY` is present. The credential is decrypted by sops-nix directly to the profile-local `.env` with mode 0400. Candidates, plans, drift reports, and Nix store-facing source contain no credential value or value-derived evidence; reports say only `present` or `missing`.

## Verification commands

From `applications/hermes-agent/math-tutor-bundle`:

```sh
python scripts/refresh_manifest.py --write
PYTHONDONTWRITEBYTECODE=1 python tests/test_bundle.py -v
PYTHONDONTWRITEBYTECODE=1 python tests/test_first_set.py -v
python scripts/run_behavior_parity.py --fixture behavior-fixture.json --self-test
nix-build default.nix --argstr host lawliet --no-out-link
nix-build default.nix --argstr host watari --no-out-link
```

From `applications/hermes-agent`:

```sh
PYTHONDONTWRITEBYTECODE=1 python tests/test_profile_registry_check.py -v
```

These commands verify static candidates, fixture-only materialization, and harness oracles. They do not switch either host or establish real model parity.
