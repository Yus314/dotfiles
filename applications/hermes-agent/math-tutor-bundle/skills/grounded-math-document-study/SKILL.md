---
name: grounded-math-document-study
description: Use when a long, formula-heavy mathematics PDF must support repeatable source-grounded QA, citations, structural maps, or proof study. Covers source/version pinning, multimodal representations, hybrid retrieval, locate-read-verify, evidence contracts, and evaluation.
version: 1.3.0
created_by: agent
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [mathematics, pdf, long-document, rag, provenance, citations, evaluation]
---

# Grounded mathematics document study

Use this skill for recurring work over mathematics textbooks, lecture notes, monographs, or long papers where exact formulas, theorem boundaries, cross-references, and page-grounded answers matter.

This skill complements:

- `math-book-study-workflow`: book registration, note layout, Socratic exercise sessions, and durable learning logs;
- `cross-machine-study-environments`: source authority and safe cross-host artifact handling.

Its narrower responsibility is **trustworthy source handling and evidence-backed reading of long mathematical documents**.

## Core principle

Do not equate any one of the following with understanding:

- the PDF fits in the model context;
- OCR or PDF-to-Markdown completed;
- retrieval found a plausible chunk;
- the answer is correct-looking;
- the answer includes a citation.

Treat document understanding as a pipeline:

```text
source identity
→ structured extraction and page images
→ localization
→ contiguous reading and reference following
→ mathematical interpretation
→ claim-level evidence verification
→ answer or abstention
```

## When to use

Use when the user asks to:

- make a long mathematics PDF repeatedly usable by AI;
- compare whole-context, RAG, vision, or agentic reading methods;
- ground theorem/proof/formula answers in exact pages;
- update a canonical textbook PDF without breaking citations;
- design a hybrid text/image/formula index;
- evaluate extraction, retrieval, citations, or abstention.

For one-off theorem explanations with no persistent source, use ordinary mathematics tutoring instead.

## Workflow

### 1. Pin the source

Record:

- canonical path and official source URL;
- edition and embedded revision metadata;
- SHA-256, byte size, page count;
- PDF-page to printed-page mapping status;
- verification date;
- prior canonical revision and hash, if replaced.

Do not conclude that a canonical PDF is missing merely because an environment variable is unset. Check the documented default artifact root. Do not trust a website's visible date, local filename, or Downloads copy as source identity.

If a fresh official download differs, follow `references/research-evidence-and-source-drift.md`: compare page-level extracted text and representative rendered pages, archive the old source, publish the new source atomically, update metadata, and invalidate derived artifacts by hash.

### 2. Keep dual/multiple representations

Use a lossless source-derived layer, not Markdown alone. For a born-digital mathematical PDF, benchmark representative prose, formula, matrix, diagram, exercise, and proof pages before selecting extraction roles. A strong default is page-preserving layout text for search, PyMuPDF-like native geometry for structure/provenance, and source-bound page images for exact mathematical authority. Markdown-oriented conversion must pass formula-completeness spot checks before it is trusted.

See `references/native-pdf-dual-representation.md` for the concrete dual-representation schema, page-label handling, split number/title object parsing, evidence-group evaluation, and final verification gate.

Treat `objects.jsonl` as heuristic candidates until boundary audits prove otherwise. If candidate texts absorb later headers, prose references become objects, or all proofs are forced to one page, build a separate blocks-derived verified graph instead of adding edges over contaminated candidates. Bind graph nodes and edges to source/input hashes, reconstruct multi-page spans from styled headers, quarantine unresolved candidates, and integrate graph validation into the ordinary project validator. See `references/verified-structure-graphs.md` for the schema, detection rules, transition-boundary handling, retrieval integration, and blind-holdout lock pattern.

```text
manifest.json
pages.jsonl        # page, printed page, bbox, reading order, provenance
objects.jsonl      # section, definition, theorem, proof, example, exercise
page-images/
formula-images/
```

For important formulas retain:

1. original page/region image;
2. LaTeX or MathML candidate;
3. search-normalized representation.

A generated formula string is not final evidence. Re-render or visually compare it when exact signs, scripts, fonts, matrices, or diagram layout matter.

### 3. Route retrieval by question type

For notation-heavy queries, use a conservative typed sidecar representation rather than destructive global synonym replacement. Preserve surface spans, require type/context guards for overloaded syntax, and generate a small number of focused retrieval variants. See `references/typed-mathematical-query-normalization.md`.

Fuse, rather than prematurely choose between:

- **lexical/exact/BM25**: theorem numbers, exercise IDs, notation, quotations;
- **semantic text**: paraphrases and conceptual relations;
- **visual page/region**: formulas, figures, tables, layout, OCR failures;
- **hierarchical map**: chapter roles and global structure.

Prefer logical units—definition, theorem, proof, example, exercise, section—over fixed token chunks. Expand a proof hit to a contiguous range from theorem statement through proof end, then follow cited definitions or lemmas.

For compound questions, do not retrieve only against the undivided question. Decompose it into atomic evidence needs, embed each need separately, reserve one seed per need, and then use source-bound section/object structure to complete nearby definition→result/proof/example chains. Local completion should search around a seed belonging to a different need, use role as a modest ranking bonus rather than an absolute override, and compare typed need terms against source object text rather than titles alone. Keep an independent holdout frozen while tuning on a separate source-first development set. See `references/atomic-evidence-completion.md` for the implementation and evaluation pattern.

Use explicit object-type fields when matching evidence roles; normalized verified titles may no longer contain words such as `definition` or `result`. Prefer source direction by role—definition evidence often lies before a result seed, while result/proof/example evidence generally follows a definition seed. Emit continuation pages only from verified source spans.

Track anchor selection separately from local completion. A verified graph can complete a chain after one correct seed, but cannot repair every need whose anchors all land in the wrong section. Return an evidence-coverage status per need and set `evidence_complete=false` when required roles or groups are absent; do not present an incomplete chain as a fully grounded answer.

Keep a verified-object semantic corpus separate and opt-in until ablation shows that it preserves grouped evidence coverage. Cleaner boundaries and fewer objects can change score density and regress ranking; structural correctness alone does not justify promoting a new embedding corpus.

### 4. Locate, read, verify

1. Classify the query as lookup, concept, formula, proof, cross-reference, or global synthesis.
2. Locate candidate pages/objects.
3. Read the relevant contiguous source range.
4. Follow references needed by the claim.
5. Check formulas, figures, and layout against page images.
6. Build a claim-to-evidence mapping.
7. Answer only supported claims; label inference or abstain.

Do not use a hierarchy summary, contextual prefix, graph node, or AI draft as the final citation source.

### 5. Use an explicit answer contract

```text
[Source verified]
- PDF page / printed page
- definition, theorem, exercise, or region
- supporting text or formula

[Tutor interpretation]
- intuition, examples, connections

[Unverified / inferred]
- explicit uncertainty
```

When tutoring, this contract does not replace Socratic guidance. Preserve the learner's attempt and hint ladder while keeping factual source claims grounded.

### 6. Evaluate layers separately

Build a small hand-reviewed gold set before adding a large graph or fine-tuned model. Compare:

- whole-context baseline;
- lexical/text retrieval;
- visual/page retrieval;
- hybrid retrieval;
- agentic `locate → read → verify`.

Measure separately:

- extraction and formula spot checks;
- page Hit@1/3/5 and wrong-section rate;
- required-evidence-group recall for cross-page or noncontiguous questions;
- fraction of questions for which every required evidence group was recovered;
- answer correctness;
- citation correctness and completeness;
- complete page→region→fact→answer chain rate;
- unsupported-claim rate;
- abstention accuracy;
- latency, tool calls, and storage/cost.

For source-first paraphrase holdouts, audit semantic overlap against every existing gold/holdout row before drafting, avoid inspecting current route or retrieval outputs, and attach stable claim IDs with claim-specific evidence groups. See `references/native-pdf-dual-representation.md` for the full independent-holdout procedure and JSONL shape. When freezing a set, record its file SHA-256 and create a lock artifact containing the source hash, exact first-run configuration, run/report IDs, evaluation timestamp, and an explicit no-rerun/no-tuning policy. Poor first results are durable evidence, not an invitation to reuse the holdout as development data.

For multi-evidence questions, put alternatives inside one evidence group and independently required pages/ranges in separate groups. Do not let one hit on a broad accepted-page union count as a complete proof or synthesis chain. Include at least one version-boundary unanswerable question so the system must decline claims about an edition absent from the canonical corpus.

Add a theorem/proof dependency graph only after measured failures show that simpler structure-aware retrieval is insufficient.

## Study-log boundary

Keep source-derived artifacts outside curated learner notes when possible. In learner-facing notes:

- raw external-AI structure output belongs in `book-ai-draft.md`;
- compressed maps remain `partially verified` until checked;
- exact theorem/proof claims point back to the canonical source;
- exercise and confusion logs record learner attempts and understanding changes, not ingestion success.

## Pitfalls

- Treating advertised context length as uniform whole-book use.
- Treating OCR text or Markdown as the mathematical source of truth.
- Feeding all page images to a VLM and assuming it will localize evidence.
- Splitting theorem statements from proofs with fixed token chunks.
- Using only semantic embeddings for exact notation and theorem IDs.
- Citing AI-generated summaries or contextual metadata as source text.
- Reporting answer correctness without evidence-chain correctness.
- Updating a PDF in place without archiving the old hash or invalidating indexes.
- Claiming full revision equivalence from equal page counts or a few sampled pages.
- Building GraphRAG before measuring whether simpler hybrid retrieval fails.
- Trusting attractive Markdown without checking whether displayed formulas or matrices disappeared.
- Treating running headers as definitions/theorems when parsing unnumbered object headings.
- Promoting heuristic `candidate_unverified` objects into a structural graph without auditing absorbed later headers, prose-reference false positives, and multi-page proof boundaries.
- Ending an object only at the next numbered header and thereby assigning next-page transition prose such as “The next result …” to the previous example.
- Recognizing only `Section 3E ...` and missing bare first-page headings such as `3E Products ...`, which silently assigns boundary pages to the previous section.
- Reusing the compound question's semantic vector for every atomic evidence need; this makes the decomposition operationally meaningless.
- Letting object type absolutely override relevance, so any unrelated `Proof` or `Definition` outranks a relevant result.
- Choosing a global consensus section from generic vocabulary instead of completing a chain locally around cross-need seeds.
- Reporting flat Hit@K as citation completeness when a proof or synthesis needs several independent evidence groups.
- Reusing a green test/evaluation result after a later scoring, parser, or validation edit without rerunning the full gate.

## Reference

See `references/research-evidence-and-source-drift.md` for the condensed research rationale, deterministic revision-comparison pattern, and atomic source-update checklist.
