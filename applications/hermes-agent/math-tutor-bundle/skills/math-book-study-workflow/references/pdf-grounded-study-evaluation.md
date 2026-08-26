# PDF-grounded textbook study: ingestion and evaluation

Use this reference when a mathematics textbook PDF is a recurring source, especially when it contains scans, equations, or figures.

## Treat PDF understanding as a pipeline

Audit these layers independently:

1. file intake
2. canonical source identity/version
3. direct text extraction
4. OCR for scans
5. page retrieval
6. image interpretation for equations/figures
7. grounded tutoring and citations
8. retention and transfer assessment

A strong tutoring model cannot recover text or notation that was never extracted or shown to it.

## Pin the source before building notes

Record in book metadata:

- canonical source path
- SHA-256 (label the hash algorithm correctly)
- byte size
- PDF page count
- edition/revision
- printed-page mapping status: verified or inferred

If a corrected/replaced PDF appears, compare hash and page count before reusing old page citations or indexes. Rebuild or create an explicit page map when versions differ.

Do not leave this as a documentation-only contract. Before every index rebuild:

1. validate the canonical file's hash, size, and page count;
2. reject page artifacts whose recorded source path/version differs;
3. store `source_id` and `source_sha256` in every index row or index manifest;
4. fail closed on mixed-source page Markdown.

When two editions appear compatible, state the evidence narrowly. A page-range render comparison proves only that range at that DPI; it does not prove byte identity, full-book equivalence, or tiny mathematical glyph equality. Record range, DPI, page count, and differing pages. Add higher-DPI spot checks for equation/figure-heavy pages when those details matter.

## Choose the route by page type

Probe several representative pages before extraction.

```text
native text PDF -> direct page-preserving extraction
scanned text page -> OCR for lexical retrieval
figure/equation page -> retrieve first, then render/select image for vision
```

OCR is often sufficient to locate a theorem or concept but unreliable for subscripts, signs, partial derivatives, matrices, diagrams, and equation layout. Do not force OCR to be the sole source for mathematical notation. Preserve raw OCR, then add short verified formula/figure anchors for high-value pages.

Treat cached page images and verified notes as derived artifacts with provenance, not merely files that happen to exist. For rendered images, store canonical `source_id`, source SHA-256, PDF page, DPI, image SHA-256, and generation time in a manifest. A router should expose an image or verified anchor only when the file exists and its recorded provenance/hash still matches; stale CSV metadata or a path string alone is not sufficient.

When publishing a rendered page atomically, remember that a system temporary directory may be on another filesystem from the study project. Render to the temporary location, copy to a staging file **inside the destination directory**, then call `os.replace(staging, destination)`. Direct `os.replace` across filesystems can fail with `EXDEV`; the durable pattern is destination-local staging, not abandoning atomic replacement.

## Retrieval-before-vision workflow

1. Search lexical text plus theorem names, aliases, and section metadata.
2. Narrow to 2–5 pages.
3. Prefer verified anchors over raw OCR for grounding, but do not let verification status overwhelm query relevance in ranking.
4. Inspect selected page images for exact equations and diagrams.
5. Separate source-supported claims from tutor explanations.
6. Cite PDF page and printed page separately; label inferred mappings.

### Japanese lexical retrieval pitfalls

FTS5 `unicode61` does not provide Japanese morphological segmentation, while FTS5 `trigram` cannot retrieve one- or two-character terms. A robust small-corpus design fuses:

- exact substring coverage for direct user terms;
- trigram BM25 for direct terms of at least three characters;
- unicode61/BM25 for English, OCR-separated text, and aliases.

Preserve user-supplied word boundaries *before* applying OCR-space normalization. Otherwise a query such as `完全代替財 ビール 直線` may be collapsed into one unsearchable token. Downweight generic one- and two-character substring terms so words such as `比` do not dominate informative concepts. Do not return early after the first trigram hit: fuse trigram, short-term substring, and alias candidates. Probe trigram availability at index-build time and retain a unicode/substring fallback for SQLite builds without that tokenizer.

Evaluate ranking variants instead of assuming manually verified pages deserve a large score bonus. Verification quality and query relevance are distinct signals; verified content is often best used during grounding after retrieval.

Useful retrieval metrics:

- Hit@1/3/5 when success means “at least one accepted page appeared”
- true Recall@K only when measuring the fraction of all labeled relevant pages retrieved
- MRR
- wrong-section rate
- verified-page hit rate
- page-citation error rate

Always name Hit@K and Recall@K correctly. Record the mean number of accepted pages per question because broad page ranges make Hit@K easier. Treat a gold set used during development as a regression set, not a blind generalization test. Freeze ranking before running a separate paraphrase/held-out set, and do not tune on that first result.

Govern evaluation labels separately from ranking. Accepted pages should be justified by inspected source boundaries, not by whichever pages the current search returns. If a failure reveals that a gold label is too narrow—for example, a definition begins on one page but the queried equation is explicitly moved to the next—inspect the source, record the evidence, and amend the label with a reason. Do not silently widen labels to turn failures green. Preserve the pre-change run so the effect of a legitimate label correction remains auditable.

A post-change holdout written by the same operator is useful but not truly blind. Label it `author-created post-change holdout`, report poor results without retuning, and classify failures by retrieval mechanism (missing synonym, OCR mismatch, compositional paraphrase, wrong section). Before adding semantic retrieval or a reranker, create a second untouched set or obtain third-party questions; otherwise the first holdout becomes another development set. A perfect regression Hit@5 alongside weak holdout performance is evidence of overfitting or lexical brittleness, not a reason to average the scores.

## Learning evidence must outlive the chat

A good dialogue is not enough if the durable ledger remains an empty template. After a substantive session, record only the learning delta:

- object/theorem/exercise
- initial closed-book attempt
- specific misconception
- hint level
- corrected reconstruction
- confidence
- source page(s)
- next review date

Then retest with changed prompts:

- immediate: reconstruct after correction
- about 1 day: same concept, different wording
- about 3 days: example/non-example or proof skeleton
- about 7 days: unseen transfer problem

For an append-oriented machine-readable ledger, validate the entire existing file before writing, lock concurrent writers, reject duplicate `(attempt_id, review_stage)` records before append, flush/fsync, and use sequence numbers plus a SHA-256 hash chain when later edits should be detectable. Validate ranges, timestamps, review ordering, confidence, hint level, outcome, and orphan references. Describe a hash chain accurately: it detects tampering but does not make a normal filesystem file immutable.

Do not infer progress from an AI overview, page count, or a completed ingestion pipeline.

## Minimal benchmark matrix

Compare:

- file/path only
- direct extracted text
- OCR top-k
- OCR top-k plus verified anchors
- verified anchors plus selected page images

Include literal lookup, definition relation, proof/derivation, equation exactness, figure interpretation, boundary cases, synthesis, and transfer. Report extraction, retrieval, answer correctness, citation correctness, and delayed retention separately.

## Final verification discipline

After implementation, run an independent skeptical review for evaluation leakage, stale derived artifacts, provenance gaps, duplicate ledger writes, and portability assumptions. If that review causes any code or data change, rerun the complete quality gate afterward—syntax checks, unit tests, source validation, index rebuild, retrieval regression, held-out evaluation, routing smoke tests, ledger smoke tests, and metadata validation. Never report an earlier green run as proof for later untested edits; name the last verified checkpoint and list post-checkpoint changes as unverified until exercised.
