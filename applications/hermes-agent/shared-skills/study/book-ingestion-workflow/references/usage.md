# Book Ingestion Workflow Reference

Locate the helper dynamically so this reference works from local or shared skill roots:

```bash
BOOK_INGEST="<skill_dir returned by skill_view(name='book-ingestion-workflow')>/scripts/book_ingest.py"
```

Core commands:

```bash
# Initialize empty project
python "$BOOK_INGEST" init ~/books/my-book \
  --title '本のタイトル' --author '著者名' --book-id my-book

# Ingest PDF/Markdown/text
python "$BOOK_INGEST" ingest /path/to/book.pdf ~/books/my-book \
  --title '本のタイトル' --author '著者名' --book-id my-book

# Rebuild indexes from extracted/full.md
python "$BOOK_INGEST" index ~/books/my-book

# Validate generated files
python "$BOOK_INGEST" validate ~/books/my-book

# Initialize evaluation harness
python "$BOOK_INGEST" eval-init ~/books/my-book

# Evaluate retrieval against eval/golden-questions.jsonl
python "$BOOK_INGEST" eval-retrieval ~/books/my-book \
  --top-k 5 --run-id baseline

# Evaluate deterministic answer/citation/refusal checks
python "$BOOK_INGEST" eval-answers ~/books/my-book \
  --answers eval/runs/manual-answers.jsonl --run-id baseline
```

Generated project layout:

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
└── eval/
    ├── golden-questions.jsonl
    ├── runs/
    ├── reports/
    └── judge-prompts/
```

Evaluation gold question example:

```jsonl
{"id":"q001","question":"定義Aとは何ですか？","answerable":true,"expected_answer_points":["対象を構造として見る考え方"],"expected_sources":[{"chunk_id":"my-book-0003"}],"must_cite":true}
```

Answer evaluation input example:

```jsonl
{"question_id":"q001","answer":"定義Aとは... [my-book-0003]","citations":["my-book-0003"]}
```
