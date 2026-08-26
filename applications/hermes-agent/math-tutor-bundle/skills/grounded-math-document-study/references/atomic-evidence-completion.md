# Atomic multi-evidence retrieval and structure-aware completion

Use this reference when a question needs several independently required source objects or pages, especially definition→result/proof/example chains.

## Durable design pattern

1. **Freeze an independent holdout before tuning.** Run it once, preserve the run artifact, and do not rerun it while adjusting the route. Diagnose failure classes only.
2. **Create a separate source-first development set.** Give independently required evidence separate `required_evidence_groups`; alternatives belong in one group.
3. **Decompose the question into atomic evidence needs.** Preserve each clause, assign a role (`definition`, `result`, `proof/derivation`, `example`, `comparison`, or `lookup`), and carry typed entities such as map signatures, polynomial spaces, compositions, quotients, and cosets.
4. **Embed each need separately.** Never reuse the vector for the whole compound question as every need vector; that nullifies semantic decomposition. Batch need embeddings for evaluation efficiency.
5. **Reserve one seed per need.** Select one unique initial page/object for each need before allowing one need to consume the remaining top-k budget.
6. **Complete chains locally.** For each need, inspect source-bound objects near a seed belonging to a *different* need. Prefer the same section and adjacent page, require role compatibility, and rank with typed-query overlap against object text—not title alone.
7. **Fill remaining slots only after local completion.** Keep the resulting evidence plan small and inspectable.
8. **Evaluate grouped coverage.** Report both evidence-group recall@k and the fraction of questions with all required groups recovered. Flat Hit@k is insufficient.

## Structure index requirements

A source-bound structure artifact should contain:

- source SHA and hashes of the page, block, and candidate-object inputs;
- chapter/section ranges and object→section assignments;
- verified object source order;
- `next_in_source`, page-span, and statement↔proof edges;
- header block IDs and enough provenance to reconstruct and hash-check original object text;
- a candidate-hit→verified-node mapping plus quarantine records for unresolved candidates.

Do not assume heuristic object text is a valid graph substrate. Audit for later-header absorption, prose references misclassified as results, and proofs forced into single-page spans. When those failures are material, reconstruct verified nodes from styled physical blocks and use candidate objects only as retrieval aliases. See `verified-structure-graphs.md`.

Section parsers must recognize both running headers such as `Section 3E ...` and first-page bare headings such as `3E Products and Quotients ...`. Verify section transitions on representative first pages; otherwise adjacent evidence can be assigned to the previous section.

## Ranking cautions

- Object role is a small bonus, not an absolute override. Promoting every `Proof` or `Definition` above relevance produces unrelated chapter hits.
- Match roles against explicit `object_type`/`object_kind` fields. Verified parsers often strip prefixes such as `definition:` from normalized titles, so title-only role matching silently fails.
- Prefer source direction by role: definition evidence often precedes a result seed; derivation/result/proof/example evidence usually follows a definition seed.
- Do not choose a global consensus section merely because generic needs have candidates there. Terms like “proof”, “product”, and “definition” occur throughout a textbook.
- For ambiguous previous/next pages, compare the typed need against source object text. Titles alone may not distinguish “dual basis” from “dual of a product”.
- Keep deterministic normalization conservative and typed. Do not destructively replace overloaded notation globally.
- Measure wrong-section anchor errors separately. Local completion can repair a missing adjacent object after one good seed, but it cannot rescue every need whose anchors all land in another section.
- Compute need-level coverage and set `evidence_complete=false` when required roles/groups are absent or the page budget truncates a chain.

## Evaluation protocol learned from the LADR pilot

A six-question source-first development set initially had `all evidence groups@5 = 0.50`. Atomic decomposition alone did not improve it; some variants degraded it. The successful combination was:

- per-need semantic vectors;
- one seed per need;
- source-bound section/object structure;
- cross-need same-section adjacent-page completion;
- object-text overlap using typed query variants.

That combination reached `all evidence groups@5 = 1.00` on the development set. This is development evidence only, not a generalization claim. In the same pilot, a fresh source-first blind set later recovered all groups for only 2 of 9 answerable multi-evidence questions despite much better flat Hit@5. The remaining failures were chiefly wrong-section anchors, notation gaps, and one missing page from otherwise relevant chains. Thus a verified graph improves post-anchor completion but does not establish general retrieval quality.

Freeze each independent holdout with a lock record containing the set SHA-256, source SHA, exact configuration/model, first-run ID, timestamp, and a no-rerun/no-tuning policy. Diagnose failure classes from the preserved run, then create a new development set and eventually a new blind set; never convert the failed holdout into a tuning loop.

A verified-object semantic corpus should also be introduced as a separate ablation. Cleaner object boundaries may still reduce grouped coverage because score density and fusion calibration change. Do not auto-promote it merely because its source spans are better.

## Verification gate

After the final parser or ranking edit, rerun:

1. focused unit tests, including bare-section headings and multi-need chain completion;
2. canonical project validation, including structure hashes;
3. development ablation report;
4. exactly one fresh blind-holdout evaluation.

Do not cite a passing test run that predates the final edit as verification of the final state.
