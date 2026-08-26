# Blocks-derived verified structure graphs for mathematical PDFs

Use this reference when heuristic `objects.jsonl` extraction has enough boundary errors that it cannot safely drive proof ranges, section completion, or semantic indexing.

## Why a second graph is needed

A candidate object corpus is useful for lexical retrieval but is not automatically a structural authority. Audit it before graph construction:

- count objects whose text includes a later accepted object header;
- count candidate rows created from ordinary prose references such as “5.19 and Exercise …”;
- compare single-page candidate spans with visibly multi-page proofs;
- check split number/title headings where `y0` differs but vertical boxes overlap;
- distinguish missing object numbers from equation numbers, so validation does not require a gap-free sequence;
- record `candidate_unverified` status instead of silently upgrading it through graph inclusion.

In one native textbook pilot, 366 of 896 heuristic candidate texts included a later numbered object and every candidate had a single-page range. The correct response was not more graph edges over those candidates; it was a separate, source-bound reconstruction from physical blocks.

## Recommended artifact shape

Keep candidate retrieval artifacts intact and generate a separate verified graph:

```text
structure/
  manifest.json
  nodes.jsonl
  edges.jsonl
```

`manifest.json` should bind:

- canonical source ID and SHA-256;
- hashes and record counts for `pages.jsonl`, `blocks.jsonl`, and candidate `objects.jsonl`;
- builder/config version;
- node and edge file hashes;
- counts by chapter, section, numbered object, proof, rejected/quarantined candidate;
- generation timestamp and verification status.

Every source-derived node retains header block IDs and a source span:

```json
{
  "start_block_id": "...",
  "end_block_id": "...",
  "block_ids": ["..."],
  "pdf_pages": [21, 22],
  "printed_pages": [7, 8],
  "text_sha256": "..."
}
```

Store normalized source text or provide a deterministic block-based reconstruction and verify its hash. Do not cite a graph summary instead of these source blocks/pages.

## Deterministic reconstruction

### 1. Preserve physical source order

Use `(pdf_page, JSONL row order)` as the primary order. Treat `block_no` and `line_no` as diagnostics. Remove running headers and footers from object spans without deleting them from the source corpus.

### 2. Detect chapter and section headings by style

Use text, font, size, color, and bbox together. Verify expected chapter/section counts on the canonical source. Handle chapter-only scopes explicitly; do not invent labels such as `4A` when the source has no such section.

Recognize both running headers (`Section 3E …`) and bare first-page headings (`3E Products …`). A parser that misses the bare heading silently assigns the first section page to the previous section.

### 3. Detect numbered object headers narrowly

For split number/title headers:

- require a numbered block with the publication’s header font/size signature;
- require the title partner on the same page and to the right;
- use vertical overlap ratio, not only `abs(y0_1-y0_2)`;
- require an explicit kind (`definition:`, `example:`) or the publication’s verified styled-result signature.

For inline `N.N title`, require the same style evidence. Regex matching alone is insufficient because ordinary prose references also begin with theorem numbers.

### 4. Detect proofs by the publication’s explicit proof style

Require exact proof-label text plus font/size/color signature. Attach a proof only to the previous statement-like object in the same section. Leave unmatched proofs unattached rather than guessing.

### 5. Bound source spans with accepted structural anchors

End an object at the next accepted object/proof header or section boundary. Proof spans can naturally cross pages. Also detect explicit transition prose such as “The next result …” or “Our next goal …”; otherwise bridge paragraphs on the next page may be falsely assigned to the previous example and create an unjustified continuation page.

Do not impose a fixed line limit. Do not derive page ranges from `anchor_page ± 1`.

## Minimal edge vocabulary

Prefer factual source-order and containment edges:

- `contains` (chapter→section, section→object);
- `next_in_source` within one section;
- `has_statement` / `has_proof`;
- `starts_on_page` / `continues_on_page`;
- `explicit_object_reference` only for uniquely resolved, source-explicit references.

Do not invent semantic edges such as `definition_implies_theorem` merely because objects are adjacent. Retrieve type-constrained chains over `next_in_source` instead.

## Validation gate

Fail closed when any check fails:

- source and input hashes match;
- node IDs are unique;
- all edge endpoints exist;
- chapter/section order and expected counts match the canonical source;
- each object belongs to exactly one section;
- object text reproduces `text_sha256`;
- no object span contains another verified header except its own;
- statement/proof endpoints are in the same section;
- page edges exactly match source-span pages;
- no reasonless adjacent pages are emitted.

Integrate this validation into the ordinary project validator. A separate successful builder command is not enough if later code can consume a stale graph.

## Retrieval integration

Map heuristic lexical/semantic hits to verified nodes through explicit `candidate_object_ids`, exact object number/page, or a conservative proof-page resolver. If resolution fails, do not structure-expand the hit.

For compound questions:

1. reserve one seed per atomic need;
2. complete a need around a seed belonging to a different need;
3. require same-section locality and role compatibility;
4. use object type fields directly—do not assume the title still contains `definition:` or `result` after normalized parsing;
5. prefer source direction by role: definitions often precede statement/proof evidence, while derivations/results/examples generally follow their defining seed;
6. score typed need terms against verified object text, not title alone;
7. emit actual continuation pages from source spans with explicit reasons.

Local graph completion cannot repair an anchor that landed in the wrong section. Track wrong-section rate and need-level section coverage separately from post-anchor completion quality.

## Semantic corpus caution

A verified-object embedding corpus removes contaminated text and gives stable IDs, but it can still reduce retrieval metrics because:

- fewer objects change score density;
- shorter, cleaner spans remove broad lexical clues that embeddings exploited;
- fusion weights were calibrated on the old corpus;
- normalized titles no longer contain kind words unless object type is embedded explicitly.

Build verified semantic vectors as a separate opt-in artifact. Bind them to the verified-node file hash. Run a development ablation before promotion. If all-evidence-group coverage regresses, keep the existing semantic corpus as the default and preserve the verified corpus as a pilot; structural cleanliness is not evidence of ranking superiority.

## Blind-holdout discipline

After selecting a configuration on development data:

- commission a source-first holdout creator that cannot inspect route runs/reports;
- assert ID sequence, schema, source hash, page ranges, answerable balance, multi-evidence count, and overlap with existing sets;
- write the set once and record its SHA-256;
- evaluate the chosen configuration once;
- create a lock artifact containing set hash, source hash, run ID, model/config, timestamp, and “do not rerun or tune” policy;
- preserve poor results and classify failure modes without retuning on that set.

A perfect development all-groups score followed by low blind all-groups recovery is evidence that anchor selection or notation coverage still fails to generalize. Do not widen accepted pages or repeatedly rerun the holdout to hide that gap.
