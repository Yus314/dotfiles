# Native mathematical PDFs: dual representation and evidence-group evaluation

Use this reference for born-digital mathematics textbooks that must support repeated grounded lookup, exact formulas, cross-page proofs, and citation evaluation.

## Benchmark representative pages first

Do not choose an extractor from reputation alone. Probe pages covering ordinary prose, definitions, displayed equations, dense matrices, diagrams, exercises, and page-spanning proofs.

A successful practical pattern is:

- `pdftotext -layout`: canonical searchable page text and strong spatial reading order;
- PyMuPDF native extraction: page labels, blocks, spans, fonts, bbox geometry, links, drawings, and fast rendering;
- source-bound page images: authority for exact matrices, stacked fractions, integrals, diagrams, and other two-dimensional notation.

Markdown-oriented conversion can produce attractive prose while silently omitting formula regions. Never use it as the sole mathematical representation without formula-completeness spot checks.

## Recommended artifact shape

```text
canonical source PDF (source ID + SHA-256 + size + page count)
├── layout-text/       # page-preserving searchable text
├── text/              # native extractor text
├── pages.jsonl        # page labels, printed-page mapping, provenance
├── blocks.jsonl       # text/span geometry
├── objects.jsonl      # heuristic retrieval candidates, explicitly unverified
├── structure/         # optional blocks-derived verified nodes/edges + manifest
├── page-images/       # exact visual authority
└── index.sqlite       # atomic lexical/object/page index
```

Every derived record and image carries the canonical source ID and hash. Search, read, render, and index operations fail closed when source identity changes. If a verified structure or semantic corpus exists, ordinary validation also checks its input/output hashes so stale optional artifacts cannot be consumed silently.

## Page mapping

Preserve separately:

- one-based PDF page;
- PDF page label, including Roman front matter;
- printed page;
- mapping status such as `frontmatter_roman`, `verified_body_offset`, `inferred`, or `unknown`.

Do not apply a body offset to front matter. Verify multiple body samples before marking an offset verified.

## Mathematical object parsing

Number and title often arrive as separate lines at nearly the same vertical coordinate. Merge those lines before classifying a numbered definition/result/example; use vertical overlap ratio rather than a brittle absolute `y0` threshold.

Running headers can resemble object headings. Avoid classifying every unnumbered line starting with “Definition” or “Theorem”; use narrow unnumbered rules such as publication-styled proof markers. Likewise, do not accept every `N.N ...` prose line as a result—require an explicit kind or verified font/color/header signature.

Keep heuristic candidate boundaries explicitly unverified. Audit how often candidate text contains a later accepted header and whether multi-page proofs are collapsed to one page. If those rates are material, construct a separate verified graph from physical blocks instead of treating candidate text as complete evidence. End verified spans at accepted headers/section boundaries and explicit transition prose; represent actual continuation pages directly. See `verified-structure-graphs.md`.

## Evaluation with required evidence groups

Maintain two development sets:

1. Simple retrieval: exact definitions, theorem IDs, notation, exercise lookup, source identity, unanswerable questions.
2. Citation-chain retrieval: cross-page proofs, noncontiguous definition-plus-criterion evidence, theorem boundary material, counterexamples, and chapter synthesis.

Encode independently required evidence as separate groups and alternatives within one group:

```json
{
  "accepted_pages": [259, 260, 287, 288],
  "required_evidence_groups": [[259, 260], [287, 288]]
}
```

Report ordinary Hit@K separately from:

- evidence-group recall@K;
- fraction of questions with all required groups recovered;
- answer correctness;
- citation correctness/completeness;
- unsupported-claim rate;
- abstention accuracy.

A high flat Hit@K can coexist with incomplete proof or citation chains.

## Independent paraphrase holdouts

When designing a post-change or retrieval-agnostic holdout, keep labeling strictly source-first:

1. Read all existing gold and holdout records before drafting; audit both IDs and semantic content, because a new wording of an old definition is still overlap.
2. Pin the canonical source ID and hash, then inspect page-preserving source text and source-bound images where formulas, matrices, or layout matter.
3. Do not run, inspect, or infer labels from current retrieval, routing, ranking, or semantic-search results. A holdout created after seeing route behavior is contaminated even if its questions are newly worded.
4. Prefer natural learner paraphrases rather than theorem titles or index-like prompts. Mix conceptual questions, examples, boundary cases, and explanations.
5. For each row, record one-based PDF pages, printed pages, independently required evidence groups, and claim-level expected content. Give each expected claim a stable claim ID and its own evidence groups.
6. Put page alternatives inside one evidence group; put independently necessary pages in separate groups. The accepted-page union is not a substitute for citation-chain completeness.
7. Include several genuinely multi-evidence questions and at least one version-boundary unanswerable. For an unanswerable row, keep accepted pages and required evidence groups empty; source-identity pages may be noted diagnostically but are not answer evidence.
8. Verify JSONL records structurally and state explicitly whether files were written and whether route results were avoided.
9. Treat route-run artifacts as prohibited inputs, not merely as data that should not influence labels: exclude `runs/`, route reports, ranking traces, and evaluation outputs from discovery and bulk reads. Enumerate and inspect only source material plus the existing gold/holdout definition files needed for overlap exclusion.
10. If the requester asks for an in-chat artifact without file changes, validate the complete JSONL from stdin or an in-memory string, verify the canonical PDF hash directly, and return every JSONL row verbatim in the final response. Do not silently persist a temporary holdout file.
11. For a source-absence negative control, use an exhaustive case-insensitive search over the canonical page-preserving text for the requested terminology and inspect the relevant table-of-contents range. Keep answer pages and evidence groups empty; put the search scope and absence rationale in the evidence summary rather than treating TOC pages as answer evidence.
12. Before freezing, assert the requested row count, exact ID sequence, exact schema keys, answerable/unanswerable balance, minimum multi-evidence count, common source hash, and JSON parseability. This is structural validation only—do not evaluate retrieval or answer quality.

A useful claim-level shape is:

```json
{
  "id": "BOOK-PH-001",
  "question": "Natural learner paraphrase",
  "answerable": true,
  "accepted_pages": [12, 13],
  "required_evidence_groups": [[12], [13]],
  "printed_pages": [4, 5],
  "expected_claims": [
    {
      "claim_id": "BOOK-PH-001-C1",
      "expected_content": "Concise source-supported claim",
      "evidence_groups": [[12]]
    }
  ],
  "source_verification_notes": "Canonical locations and verification mode"
}
```

## Version-boundary abstention

Include a gold question requesting an exact theorem/page from an edition absent from the canonical corpus. Correct behavior is to decline the attribution and identify the available edition—not to silently substitute a similarly numbered result.

## Verification gate

Before reporting completion:

1. run unit tests on synthetic PDFs;
2. ingest the entire canonical source;
3. regenerate searchable text and the index;
4. verify text/image hashes and source binding;
5. inspect Roman and body page labels;
6. run both simple and evidence-group evaluations;
7. rerun the full repository test suite after the final ranking or validation edit.

Any code or scoring change makes an earlier green checkpoint stale.

## NixOS PyMuPDF wheel runtime

On NixOS, a PyMuPDF wheel installed by `uv` can import-fail before tests run with:

```text
ImportError: libstdc++.so.6: cannot open shared object file
```

This is a runtime-library discovery problem, not a failed extraction test. Scope the GCC runtime path to the verification command instead of exporting it globally:

```bash
LIBSTDCPP=$(nix eval --raw nixpkgs#stdenv.cc.cc.lib)
LD_LIBRARY_PATH="$LIBSTDCPP/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  uv run --with pymupdf python -m unittest discover -s tests -v
```

First preserve the import traceback as evidence, then rerun the same test command with the scoped runtime path. Do not report the second green run without noting that the first failure was environmental.

## Local object embeddings with FastEmbed

Keep semantic retrieval optional and object-level first. Embed definitions/results/examples/proofs before all page blocks, bind the semantic manifest and vector file to the canonical source SHA-256, record model/dimensions/vector SHA-256, and make ordinary validation detect source or vector tampering.

On CPU, a large FastEmbed batch can spend excessive time padding heterogeneous object texts. A corpus run with a 256-item batch may stall after one batch even when single-query embedding is fast. Sort records by embedding-text length and use a smaller batch such as 32; publish through a destination-local staging file. Batch all evaluation queries in one model process instead of starting the model once per question.

Ablate separately:

```text
A: exact + lexical + evidence route
B: A + typed concept aliases
C: A + semantic objects
D: A + aliases + semantic objects
```

Do not assume more signals improve evidence completeness. Alias expansion can increase ordinary Hit@K while displacing one page from a multi-group proof or synthesis chain. Preserve the existing no-semantic route unchanged, keep semantic retrieval opt-in until latency and holdout behavior are measured, and select the simplest configuration that preserves all required evidence groups.

## Claim/citation answer contracts

Represent an answer as stable claim IDs with claim text, cited PDF pages, and canonical source SHA-256. Evaluate these dimensions separately:

- required-claim coverage;
- deterministic expected-point/term coverage;
- citation correctness: cited pages stay within the allowed evidence union;
- citation completeness: every independently required evidence group is cited;
- source integrity;
- supported and unsupported claim rates;
- abstention accuracy;
- whole-question contract pass rate.

A citation can be correct but incomplete. For example, one cited page may belong to an allowed two-page proof while omitting the second required page. Reject duplicate claim IDs, count unknown claims or out-of-gold citations as unsupported, and exclude expected explanatory claims from the required-claim denominator for unanswerable questions—the required behavior there is abstention.

Term matching is schema compliance, not mathematical correctness. Say this in reports and retain human/source review for claim truth.

## Independent paraphrase holdouts

Do not stop after a post-change holdout reaches 100%. Commission or author a new source-first set without inspecting current retrieval results, emphasize multi-evidence and notation-heavy natural questions, freeze it, and run the chosen configuration once. Preserve poor first results without tuning on the same set. A perfect development evidence-chain score can coexist with very low independent all-groups recall; that gap is evidence of lexical/benchmark overfitting and missing query decomposition or structural retrieval, not a reason to widen accepted pages.