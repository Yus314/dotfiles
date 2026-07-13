---
name: book-ingestion-workflow
description: Use when ingesting one full book/PDF into a Hermes-friendly local project for grounded QA, study, citations, and iterative reading.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [books, pdf, rag, markdown, study, local-first, hermes]
    related_skills: [ocr-and-documents, document-extraction-workflows, hermes-agent]
---

# Book Ingestion Workflow

## Overview

Use this skill to turn one book (PDF, Markdown, or text) into a local-first Hermes project that behaves like a lightweight NotebookLM/Project: structured files, `AGENTS.md` reading rules, page/chapter extraction, a table-of-contents index, structural chunks, contextual chunks, study notes, and validation.

The goal is not to paste a whole book into conversation context. The goal is to preserve the book on disk in a form Hermes can search and re-read with `search_files` and `read_file`, while keeping citations and study state grounded.

This skill includes a helper script at `scripts/book_ingest.py`.

## When to Use

Use when the user asks to:

- ingest / load / index a full book into Hermes
- make a PDF book usable for repeated Q&A
- build a local book project for study, summaries, confusion tracking, or citations
- convert a book into `AGENTS.md` + extracted text + chunks + contextual chunks
- improve performance of book-based retrieval or NotebookLM-like workflows

Do **not** use for:

- one-off quick PDF summaries where a direct `web_extract` or simple `pdftotext` is enough
- sensitive/private books that the user has not authorized you to read
- finance/health/diary data in the default profile; use the appropriate isolated profile/workflow

## Output Project Layout

The helper script creates this structure:

```text
<project>/
├── AGENTS.md
├── source/
├── extracted/full.md
├── extracted/pages/
├── extracted/chapters/
├── index/manifest.json
├── index/toc.json
├── index/chunks.jsonl
├── index/contextual_chunks.jsonl
├── summaries/book-summary.md
├── summaries/chapter-summaries.md
├── summaries/concept-map.md
├── summaries/argument-map.md
├── notes/reading-log.md
├── notes/confusions.md
└── eval/golden-questions.jsonl
```

## Quick Start

First locate the skill script with `skill_view(name="book-ingestion-workflow")`, then use the returned `skill_dir` rather than assuming a profile-local path:

```bash
BOOK_INGEST="<skill_dir returned by skill_view>/scripts/book_ingest.py"
```

All commands below use `$BOOK_INGEST`, so the same workflow works from profile-local, shared, or bundled skill directories.

### Initialize an empty book project

```bash
python "$BOOK_INGEST" init ~/books/my-book \
  --title '本のタイトル' \
  --author '著者名' \
  --book-id my-book
```

### Ingest a PDF / Markdown / text file

```bash
python "$BOOK_INGEST" ingest /path/to/book.pdf ~/books/my-book \
  --title '本のタイトル' \
  --author '著者名' \
  --book-id my-book
```

Markdown/text input also works:

```bash
python "$BOOK_INGEST" ingest ./book.md ~/books/my-book \
  --title '本のタイトル' \
  --author '著者名'
```

### Rebuild indexes from `extracted/full.md`

```bash
python "$BOOK_INGEST" index ~/books/my-book
```

### Validate generated artifacts

```bash
python "$BOOK_INGEST" validate ~/books/my-book
```

### Initialize evaluation harness

```bash
python "$BOOK_INGEST" eval-init ~/books/my-book
```

This creates `eval/golden-questions.jsonl`, `eval/runs/`, `eval/reports/`, and `eval/judge-prompts/`. Edit `golden-questions.jsonl` to add expected answer points and expected source chunk IDs.

### Evaluate retrieval

```bash
python "$BOOK_INGEST" eval-retrieval ~/books/my-book \
  --top-k 5 \
  --run-id baseline
```

Outputs `eval/runs/baseline-retrieval.jsonl` and `eval/reports/baseline-retrieval.md` with Recall@1/3/5, Precision@5, MRR, and failure rows.

### Evaluate answers/citations/refusals

Prepare an answers JSONL:

```jsonl
{"question_id":"q001","answer":"... [my-book-0003]","citations":["my-book-0003"]}
```

Then run:

```bash
python "$BOOK_INGEST" eval-answers ~/books/my-book \
  --answers eval/runs/manual-answers.jsonl \
  --run-id baseline
```

This currently performs deterministic checks: expected answer point coverage, citation ID validity, and unanswerable/refusal accuracy. Use the generated judge prompts for later LLM-as-judge scoring.

## Recommended Workflow

### 1. Decide privacy boundary

Before processing the source, classify it:

- Public book / paper / manual: normal local extraction is fine; public web extraction may be acceptable for URL PDFs.
- Private or copyrighted personal copy: keep local; do not send the contents to external research providers unless explicitly authorized.
- Health/finance/diary: stop and use the correct isolated profile or ask before proceeding.

### 2. Inspect the source type

For a URL PDF, consider `web_extract` first if the content is public. For local books:

- Native text PDF: try the included script directly.
- Scanned PDF, math-heavy book, dense tables, vertical text, or complex layout: use `ocr-and-documents` and consider `marker-pdf`, Docling, or manual high-quality Markdown extraction first.
- EPUB/DOCX: convert to Markdown/text first, then ingest the Markdown.

The script tries PDF extractors in this order:

1. `pymupdf4llm`
2. `pymupdf`
3. `pdftotext`
4. Nix fallback: `nix shell nixpkgs#poppler-utils -c pdftotext`

### 3. Run ingestion

Use a stable project path under `~/books/<book-id>` unless the user specifies another location.

Example:

```bash
python "$BOOK_INGEST" ingest ~/Downloads/book.pdf ~/books/book-project \
  --title 'Book Title' \
  --author 'Author Name' \
  --book-id book-project
```

### 4. Validate and inspect

Always validate:

```bash
python "$BOOK_INGEST" validate ~/books/book-project
```

Then inspect at least:

- `AGENTS.md`
- `index/toc.json`
- first few lines of `index/contextual_chunks.jsonl`
- `summaries/chapter-summaries.md`

Use `read_file`, not shell `cat`, for inspection.

### 5. Use the project with Hermes

CLI:

```bash
cd ~/books/book-project
hermes
```

Discord/gateway:

```text
~/books/book-project の本を対象に、第1章の重要概念を根拠付きで説明して
```

Hermes should read `AGENTS.md`, consult `index/toc.json` and `summaries/`, then search/read relevant extracted files.

## Retrieval and Study Practices

For best QA performance:

1. Use `search_files` over `index/contextual_chunks.jsonl` for conceptual or location-aware hits.
2. Use `read_file` on `extracted/chapters/` or `extracted/full.md` around the relevant section for final grounding.
3. Cite chapter/section/page when available.
4. If the answer cannot be grounded in the book project, say so explicitly.
5. For study support, maintain `notes/confusions.md` and `notes/reading-log.md` only when the user asks or clearly wants tracking.

## Improving Extraction Quality

If the output looks poor:

- Check whether the PDF is scanned or has bad embedded text.
- Try `pymupdf4llm` for fast structured Markdown:
  ```bash
  python -m pip install pymupdf pymupdf4llm
  ```
- For math, OCR, tables, forms, or complex layout, load `ocr-and-documents` and consider `marker-pdf`.
- If a better Markdown file is produced externally, rerun ingest on the Markdown file instead of the original PDF.

## Performance Evaluation Add-on

When the user wants measurable performance, create an `eval/` harness around the book project instead of judging answers ad hoc.

Recommended files:

```text
eval/golden-questions.jsonl      # question, expected answer points, expected source chunk/page ids
eval/runs/<run-id>.jsonl         # actual retrieved contexts, answer, citations, latency, token/cost notes
eval/reports/<run-id>.md         # aggregate metrics and failure analysis
```

Evaluate separate layers:

- **Extraction quality:** non-empty text, heading count, page markers, table/math/OCR spot checks.
- **Retrieval:** Recall@K, Precision@K, MRR, nDCG when expected chunk ids are labeled.
- **Context assembly:** whether retrieved context is sufficient and not too noisy.
- **Generation:** answer correctness against gold answer points, answer relevance, faithfulness/groundedness to retrieved context.
- **Citations:** every cited chunk/page actually supports the adjacent claim.
- **Unanswerability:** answerable=false cases should refuse or say the book does not support the answer.
- **Operational metrics:** latency, tool calls, context size, token/cost estimates, and failure rate.

Gold-set construction for one book should cover factual lookup, definition, explanation, cross-chapter synthesis, quote/page lookup, and unanswerable questions. Use synthetic questions to bootstrap, but manually review at least a small calibration set before trusting scores.

## Common Pitfalls

1. **Pasting the whole book into chat.** Keep the book on disk and use search/read tools.
2. **Ignoring extraction quality.** Bad OCR and broken math become bad answers. Inspect samples before trusting output.
3. **Losing page numbers.** Page markers make citations possible; prefer extractors or post-processing that preserve page mapping.
4. **Treating Memory as the book store.** Memory is for compact durable facts, not book content. Store content in the project folder.
5. **Using only embedding-style semantic search.** Exact terms, theorem names, API names, and page references often need lexical search/BM25-style matching.
6. **Using one overall score.** Split extraction, retrieval, generation, citation, and refusal metrics so regressions are diagnosable.
7. **Trusting LLM judges as absolute truth.** Use them for relative regression detection, and calibrate with human-reviewed examples.
8. **Auto-writing polished notes unasked.** For this user, keep local-first curated Markdown and only write reading notes when asked.

## Verification Checklist

- [ ] Source file copied under `source/`
- [ ] `extracted/full.md` exists and is non-empty
- [ ] `AGENTS.md` names the book and has grounding/citation rules
- [ ] `index/toc.json` exists; if empty, note that heading extraction failed or source lacks headings
- [ ] `index/chunks.jsonl` and `index/contextual_chunks.jsonl` exist and contain records
- [ ] `validate` returns `ok: true`
- [ ] At least one generated chunk was inspected for extraction quality
- [ ] User-facing answer states the project path and any extraction caveats
