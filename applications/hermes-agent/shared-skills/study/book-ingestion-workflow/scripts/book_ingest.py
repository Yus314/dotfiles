#!/usr/bin/env python3
"""Book ingestion toolkit for Hermes Agent book projects.

This script turns a single book (PDF/Markdown/text) into a Hermes-friendly
project directory: AGENTS.md instructions, extracted Markdown, page/chapter
files, structural chunks, contextual chunks, and study scaffolds.

It is intentionally local-first. Optional PDF extraction backends are imported
only when needed.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator, Sequence


@dataclass(frozen=True)
class BookMetadata:
    title: str
    author: str = "Unknown"
    language: str = "ja"
    book_id: str | None = None


@dataclass(frozen=True)
class Heading:
    level: int
    title: str
    line_no: int
    char_start: int


PROJECT_DIRS = [
    "source",
    "extracted/pages",
    "extracted/chapters",
    "index",
    "summaries",
    "notes",
    "eval",
]


HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$", re.MULTILINE)
PAGE_MARKER_RE = re.compile(r"^<!--\s*page:\s*(\d+)\s*-->\s*$", re.MULTILINE)


def slugify(text: str) -> str:
    slug = re.sub(r"[^0-9A-Za-z\u3040-\u30ff\u3400-\u9fff]+", "-", text.strip().lower())
    slug = re.sub(r"-+", "-", slug).strip("-")
    return slug or "book"


def init_book_project(project: Path, meta: BookMetadata, *, overwrite_metadata: bool = False) -> None:
    project.mkdir(parents=True, exist_ok=True)
    for rel in PROJECT_DIRS:
        (project / rel).mkdir(parents=True, exist_ok=True)

    book_id = meta.book_id or slugify(meta.title)
    agents_path = project / "AGENTS.md"
    if overwrite_metadata or not agents_path.exists():
        agents_path.write_text(render_agents_md(meta, book_id), encoding="utf-8")

    for rel, content in {
        "notes/reading-log.md": "# Reading Log\n\n",
        "notes/confusions.md": "# Confusions / 未解決の混乱\n\n",
        "summaries/book-summary.md": f"# {meta.title} — Book Summary\n\n未生成。\n",
        "summaries/chapter-summaries.md": f"# {meta.title} — Chapter Summaries\n\n未生成。\n",
        "summaries/concept-map.md": f"# {meta.title} — Concept Map\n\n未生成。\n",
        "summaries/argument-map.md": f"# {meta.title} — Argument Map\n\n未生成。\n",
        "eval/golden-questions.jsonl": "",
    }.items():
        path = project / rel
        if not path.exists():
            path.write_text(content, encoding="utf-8")

    manifest = {
        "book_id": book_id,
        "title": meta.title,
        "author": meta.author,
        "language": meta.language,
        "created_by": "book_ingest.py",
        "files": {
            "full_markdown": "extracted/full.md",
            "toc": "index/toc.json",
            "chunks": "index/chunks.jsonl",
            "contextual_chunks": "index/contextual_chunks.jsonl",
        },
    }
    manifest_path = project / "index/manifest.json"
    if overwrite_metadata or not manifest_path.exists():
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def render_agents_md(meta: BookMetadata, book_id: str) -> str:
    return f"""# Book Project Context

このディレクトリは一冊の本をHermesで参照・学習するためのプロジェクトである。

## Book
- Book ID: `{book_id}`
- Title: {meta.title}
- Author: {meta.author}
- Language: {meta.language}
- Source files: `source/`

## Directory
- `extracted/full.md`: 全文Markdown
- `extracted/pages/`: ページ単位の抽出
- `extracted/chapters/`: 章・見出し単位の抽出
- `index/toc.json`: 目次・見出し索引
- `index/chunks.jsonl`: 検索用chunk
- `index/contextual_chunks.jsonl`: 文脈付きchunk
- `summaries/`: 本全体・章・概念・論証の要約
- `notes/`: 読書ログ、混乱点、ユーザーメモ

## Answering rules
- まず `index/toc.json` と `summaries/` を確認して、本全体の位置づけを把握する。
- 質問に答える時は、必要に応じて `search_files` で関連箇所を探し、`read_file` で前後文脈を読む。
- 根拠が必要な主張には、章・節・ページ番号を添える。
- 手元資料で確認できないことは「この本からは確認できない」と明示する。
- 学習支援では、答えを急がず、必要に応じて一問ずつ確認する。
- 数式・定義・定理は、原文の記号をできるだけ保つ。
- 要約と解釈を混同しない。著者の主張とHermesの補足を分ける。

## Citation style
`[{book_id}: ch<章>, p<ページ>, <節名>]`

## Study mode
- ユーザーが「理解確認」と言ったら、1問ずつ確認する。
- ユーザーが「混乱」と言ったら、`notes/confusions.md` に追記候補を示す。
- ユーザーが「まとめ」と言ったら、章要約・用語・未解決疑問に分けて出す。
"""


def parse_markdown_headings(markdown: str) -> list[Heading]:
    return [
        Heading(level=len(m.group(1)), title=m.group(2).strip(), line_no=markdown.count("\n", 0, m.start()) + 1, char_start=m.start())
        for m in HEADING_RE.finditer(markdown)
    ]


def _heading_path_at(stack: list[tuple[int, str]], level: int, title: str) -> list[str]:
    while stack and stack[-1][0] >= level:
        stack.pop()
    stack.append((level, title))
    return [title for _, title in stack]


def _section_blocks(markdown: str) -> list[dict]:
    headings = parse_markdown_headings(markdown)
    if not headings:
        return [{"heading_path": [], "char_start": 0, "char_end": len(markdown), "text": markdown}]

    blocks: list[dict] = []
    stack: list[tuple[int, str]] = []
    for idx, heading in enumerate(headings):
        end = headings[idx + 1].char_start if idx + 1 < len(headings) else len(markdown)
        path = _heading_path_at(stack, heading.level, heading.title)
        text = markdown[heading.char_start:end]
        blocks.append({"heading_path": path, "char_start": heading.char_start, "char_end": end, "text": text})
    if headings[0].char_start > 0 and markdown[: headings[0].char_start].strip():
        blocks.insert(0, {"heading_path": [], "char_start": 0, "char_end": headings[0].char_start, "text": markdown[: headings[0].char_start]})
    return blocks


def _split_text_with_overlap(text: str, max_chars: int, overlap_chars: int) -> Iterator[tuple[int, int, str]]:
    if max_chars <= 0:
        raise ValueError("max_chars must be greater than zero")
    if overlap_chars < 0 or overlap_chars >= max_chars:
        raise ValueError("overlap_chars must satisfy 0 <= overlap_chars < max_chars")
    if len(text) <= max_chars:
        yield 0, len(text), text
        return

    start = 0
    while start < len(text):
        hard_end = min(start + max_chars, len(text))
        end = hard_end
        if hard_end < len(text):
            minimum_cut = start + max(1, max_chars // 2)
            for separator in ("\n\n", "\n", "。", ". ", " "):
                candidate = text.rfind(separator, minimum_cut, hard_end)
                if candidate >= minimum_cut:
                    end = candidate + len(separator)
                    break
        if end <= start:
            end = hard_end
        yield start, end, text[start:end]
        if end >= len(text):
            break
        start = max(end - overlap_chars, start + 1)


def estimate_pages_for_span(markdown: str, char_start: int, char_end: int) -> tuple[int | None, int | None]:
    markers = [(m.start(), int(m.group(1))) for m in PAGE_MARKER_RE.finditer(markdown)]
    if not markers:
        return None, None
    before_start = [page for pos, page in markers if pos <= char_start]
    before_end = [page for pos, page in markers if pos <= char_end]
    return (before_start[-1] if before_start else markers[0][1], before_end[-1] if before_end else markers[-1][1])


def chunk_markdown(markdown: str, book_id: str, max_chars: int = 3200, overlap_chars: int = 250) -> list[dict]:
    chunks: list[dict] = []
    for block in _section_blocks(markdown):
        for rel_start, rel_end, text in _split_text_with_overlap(block["text"], max_chars=max_chars, overlap_chars=overlap_chars):
            if not text.strip():
                continue
            char_start = block["char_start"] + rel_start
            char_end = block["char_start"] + rel_end
            page_start, page_end = estimate_pages_for_span(markdown, char_start, char_end)
            chunk = {
                "chunk_id": f"{book_id}-{len(chunks) + 1:04d}",
                "book_id": book_id,
                "heading_path": block["heading_path"],
                "page_start": page_start,
                "page_end": page_end,
                "char_start": char_start,
                "char_end": char_end,
                "type": "prose",
                "text": text.strip(),
            }
            chunks.append(chunk)
    return chunks


def contextualize_chunk(chunk: dict, title: str, author: str = "Unknown") -> dict:
    heading_path = chunk.get("heading_path") or []
    # Avoid repeating top-level book title in the human-readable section path.
    section_path = " > ".join(heading_path[1:] if len(heading_path) > 1 else heading_path) or "front matter / 全体"
    page_start = chunk.get("page_start")
    page_end = chunk.get("page_end")
    if page_start and page_end and page_start != page_end:
        page = f"p.{page_start}-{page_end}"
    elif page_start:
        page = f"p.{page_start}"
    else:
        page = "page unknown"
    context = f"このchunkは『{title}』（著者: {author}）の {section_path}（{page}）に位置する。"
    out = dict(chunk)
    out["context"] = context
    out["search_text"] = context + "\n" + chunk.get("text", "")
    return out


def write_jsonl(path: Path, records: Iterable[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")


def read_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    records: list[dict] = []
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError as exc:
            raise ValueError(f"Invalid JSONL at {path}:{line_no}: {exc}") from exc
    return records


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def find_pdftotext_command() -> list[str] | None:
    """Return a command prefix that can execute pdftotext.

    On NixOS, poppler utilities are often not installed globally. If `nix` is
    available, use an ephemeral nix shell as a dependency-free fallback.
    """
    pdftotext = shutil.which("pdftotext")
    if pdftotext:
        return [pdftotext]
    nix = shutil.which("nix")
    if nix:
        return [
            nix,
            "--extra-experimental-features",
            "nix-command flakes",
            "shell",
            "nixpkgs#poppler-utils",
            "-c",
            "pdftotext",
        ]
    return None


def extract_text_or_markdown(source: Path, output_md: Path) -> None:
    suffix = source.suffix.lower()
    output_md.parent.mkdir(parents=True, exist_ok=True)
    if suffix in {".md", ".markdown"}:
        shutil.copyfile(source, output_md)
        return
    if suffix in {".txt", ".text"}:
        output_md.write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
        return
    if suffix != ".pdf":
        raise SystemExit(f"Unsupported source type: {source.suffix}. Use PDF, Markdown, or text.")

    try:
        import pymupdf4llm  # type: ignore

        md = pymupdf4llm.to_markdown(str(source))
        output_md.write_text(md, encoding="utf-8")
        return
    except ImportError:
        pass

    try:
        import pymupdf  # type: ignore

        doc = pymupdf.open(str(source))
        parts = []
        for idx, page in enumerate(doc, start=1):
            parts.append(f"\n\n<!-- page: {idx} -->\n\n" + page.get_text("text"))
        output_md.write_text("".join(parts), encoding="utf-8")
        return
    except ImportError:
        pass

    pdftotext_cmd = find_pdftotext_command()
    if pdftotext_cmd:
        subprocess.run(pdftotext_cmd + ["-layout", str(source), str(output_md)], check=True)
        return

    raise SystemExit("No PDF extractor found. Install pymupdf4llm or pymupdf, install poppler-utils/pdftotext, or provide Markdown/text input.")


def split_pages(markdown: str, pages_dir: Path) -> int:
    pages_dir.mkdir(parents=True, exist_ok=True)
    for stale in pages_dir.glob("p*.md"):
        stale.unlink()
    matches = list(PAGE_MARKER_RE.finditer(markdown))
    if not matches:
        return 0
    for idx, m in enumerate(matches):
        page_no = int(m.group(1))
        start = m.end()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(markdown)
        (pages_dir / f"p{page_no:04d}.md").write_text(markdown[start:end].strip() + "\n", encoding="utf-8")
    return len(matches)


def write_toc_and_chapters(project: Path, markdown: str) -> None:
    headings = parse_markdown_headings(markdown)
    toc = [h.__dict__ for h in headings]
    (project / "index/toc.json").write_text(json.dumps(toc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    chapters_dir = project / "extracted/chapters"
    chapters_dir.mkdir(parents=True, exist_ok=True)
    for stale in chapters_dir.glob("ch*.md"):
        stale.unlink()

    chapter_count = 0
    for idx, heading in enumerate(headings):
        if heading.level > 2:
            continue
        end = len(markdown)
        for following in headings[idx + 1 :]:
            if following.level <= heading.level:
                end = following.char_start
                break
        chapter_count += 1
        stem = slugify(heading.title)[:60]
        (chapters_dir / f"ch{chapter_count:02d}-{stem}.md").write_text(
            markdown[heading.char_start:end].strip() + "\n",
            encoding="utf-8",
        )


def build_indexes(project: Path, *, max_chars: int = 3200, overlap_chars: int = 250) -> dict:
    if max_chars <= 0:
        raise ValueError("max_chars must be greater than zero")
    if overlap_chars < 0 or overlap_chars >= max_chars:
        raise ValueError("overlap_chars must satisfy 0 <= overlap_chars < max_chars")
    manifest = read_json(project / "index/manifest.json")
    title = manifest.get("title", project.name)
    author = manifest.get("author", "Unknown")
    book_id = manifest.get("book_id", slugify(title))
    full_md = project / "extracted/full.md"
    markdown = full_md.read_text(encoding="utf-8")

    split_pages(markdown, project / "extracted/pages")
    write_toc_and_chapters(project, markdown)
    chunks = chunk_markdown(markdown, book_id=book_id, max_chars=max_chars, overlap_chars=overlap_chars)
    contextual = [contextualize_chunk(c, title=title, author=author) for c in chunks]
    write_jsonl(project / "index/chunks.jsonl", chunks)
    write_jsonl(project / "index/contextual_chunks.jsonl", contextual)
    write_summary_scaffold(project, title=title, chunks=chunks)
    return {"chunks": len(chunks), "headings": len(parse_markdown_headings(markdown))}


def write_summary_scaffold(project: Path, title: str, chunks: Sequence[dict]) -> None:
    by_heading: dict[str, int] = {}
    for chunk in chunks:
        key = " > ".join(chunk.get("heading_path") or ["front matter"])
        by_heading[key] = by_heading.get(key, 0) + 1
    lines = [f"# {title} — Chapter Summaries", "", "以下は自動生成された章・節一覧。要約本文はHermesに依頼して追記する。", ""]
    for heading, count in by_heading.items():
        lines.append(f"## {heading}")
        lines.append(f"- chunks: {count}")
        lines.append("- summary: 未生成")
        lines.append("")
    (project / "summaries/chapter-summaries.md").write_text("\n".join(lines), encoding="utf-8")


def validate_project(project: Path) -> dict:
    required = ["AGENTS.md", "extracted/full.md", "index/manifest.json", "index/chunks.jsonl", "index/contextual_chunks.jsonl"]
    missing = [rel for rel in required if not (project / rel).exists()]
    chunks_path = project / "index/chunks.jsonl"
    chunk_count = 0
    cited_count = 0
    if chunks_path.exists():
        for line in chunks_path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            chunk_count += 1
            record = json.loads(line)
            if record.get("page_start") or record.get("heading_path"):
                cited_count += 1
    return {"ok": not missing and chunk_count > 0, "missing": missing, "chunks": chunk_count, "chunks_with_location": cited_count}


EVAL_TEMPLATE_QUESTIONS = [
    {"id": "q001", "type": "definition", "question": "この本で最初に導入される重要概念は何か？", "answerable": True, "expected_answer_points": [], "expected_sources": [], "must_cite": True, "difficulty": "easy"},
    {"id": "q002", "type": "summary", "question": "第1章の主張を3点で要約してください。", "answerable": True, "expected_answer_points": [], "expected_sources": [], "must_cite": True, "difficulty": "easy"},
    {"id": "q003", "type": "cross_chapter", "question": "第1章の概念は後半の章でどのように使われますか？", "answerable": True, "expected_answer_points": [], "expected_sources": [], "must_cite": True, "difficulty": "hard"},
    {"id": "q901", "type": "unanswerable", "question": "この本に書かれていない著者の最近の講演情報を教えてください。", "answerable": False, "expected_behavior": "この本の資料からは確認できないと答える", "expected_sources": [], "must_cite": False, "difficulty": "medium"},
]


JUDGE_PROMPTS = {
    "faithfulness.md": """# Faithfulness Judge Prompt

Question: {{question}}
Retrieved context: {{context}}
Answer: {{answer}}

Score 0-1. Extract each factual claim in the answer and verify whether it is supported by the retrieved context. Penalize unsupported or contradicted claims.
""",
    "citation-support.md": """# Citation Support Judge Prompt

For each cited claim, decide whether the cited chunk/page directly supports that claim. Return citation_support from 0 to 1 and list unsupported citations.
""",
    "answer-correctness.md": """# Answer Correctness Judge Prompt

Compare the answer to expected answer points. Score 0-1 for factual correctness and completeness. Do not reward facts that are true but absent from the expected book evidence.
""",
}


def init_eval_files(project: Path, *, overwrite_template: bool = False) -> dict:
    eval_dir = project / "eval"
    (eval_dir / "runs").mkdir(parents=True, exist_ok=True)
    (eval_dir / "reports").mkdir(parents=True, exist_ok=True)
    prompts_dir = eval_dir / "judge-prompts"
    prompts_dir.mkdir(parents=True, exist_ok=True)
    gold_path = eval_dir / "golden-questions.jsonl"
    if overwrite_template or not gold_path.exists() or gold_path.stat().st_size == 0:
        write_jsonl(gold_path, EVAL_TEMPLATE_QUESTIONS)
    for filename, content in JUDGE_PROMPTS.items():
        path = prompts_dir / filename
        if overwrite_template or not path.exists():
            path.write_text(content, encoding="utf-8")
    return {
        "golden_questions": "eval/golden-questions.jsonl",
        "runs": "eval/runs",
        "reports": "eval/reports",
        "judge_prompts": "eval/judge-prompts",
    }


def tokenize_for_search(text: str) -> list[str]:
    lowered = text.lower()
    ascii_terms = re.findall(r"[a-z0-9][a-z0-9_\-]*", lowered)
    cjk_terms = re.findall(r"[\u3040-\u30ff\u3400-\u9fff]{2,}", lowered)
    # Character bigrams help Japanese/CJK matching without external tokenizers.
    cjk_bigrams: list[str] = []
    for term in cjk_terms:
        cjk_bigrams.extend(term[i : i + 2] for i in range(max(0, len(term) - 1)))
    return ascii_terms + cjk_terms + cjk_bigrams


def lexical_search(query: str, chunks: Sequence[dict], *, top_k: int = 5) -> list[dict]:
    query_terms = Counter(tokenize_for_search(query))
    results: list[dict] = []
    if not query_terms:
        return []
    for chunk in chunks:
        text = "\n".join(str(chunk.get(key, "")) for key in ("search_text", "context", "text"))
        doc_terms = Counter(tokenize_for_search(text))
        if not doc_terms:
            continue
        overlap = sum(min(count, doc_terms.get(term, 0)) for term, count in query_terms.items())
        exact_bonus = 2.0 if query.lower() in text.lower() else 0.0
        score = overlap / max(1, sum(query_terms.values())) + exact_bonus
        out = dict(chunk)
        out["score"] = round(score, 6)
        results.append(out)
    results.sort(key=lambda item: (-item["score"], item.get("chunk_id", "")))
    return results[:top_k]


def expected_chunk_ids(question: dict) -> list[str]:
    ids: list[str] = []
    for source in question.get("expected_sources") or []:
        if isinstance(source, str):
            ids.append(source)
        elif isinstance(source, dict) and source.get("chunk_id"):
            ids.append(str(source["chunk_id"]))
    return ids


def reciprocal_rank(retrieved_ids: Sequence[str], expected_ids: Sequence[str]) -> float:
    expected = set(expected_ids)
    for idx, chunk_id in enumerate(retrieved_ids, start=1):
        if chunk_id in expected:
            return 1.0 / idx
    return 0.0


def precision_at_k(retrieved_ids: Sequence[str], expected_ids: Sequence[str], k: int) -> float:
    if k <= 0:
        return 0.0
    return len(set(retrieved_ids[:k]) & set(expected_ids)) / k


def hit_at_k(retrieved_ids: Sequence[str], expected_ids: Sequence[str], k: int) -> int:
    return int(bool(set(retrieved_ids[:k]) & set(expected_ids)))


def evaluate_retrieval(project: Path, *, top_k: int = 5, run_id: str | None = None) -> dict:
    run_id = run_id or time.strftime("%Y%m%d-%H%M%S")
    init_eval_files(project)
    questions = read_jsonl(project / "eval/golden-questions.jsonl")
    chunks = read_jsonl(project / "index/contextual_chunks.jsonl")
    rows: list[dict] = []
    answerable_rows: list[dict] = []
    for question in questions:
        if not question.get("answerable", True):
            row = {
                "id": question.get("id"),
                "question": question.get("question", ""),
                "answerable": False,
                "expected_chunk_ids": [],
                "retrieved_chunk_ids": [],
                "retrieved": [],
                "hit_at_1": None,
                "hit_at_3": None,
                "hit_at_5": None,
                "precision_at_5": None,
                "mrr": None,
            }
            rows.append(row)
            continue
        expected = expected_chunk_ids(question)
        retrieved = lexical_search(question.get("question", ""), chunks, top_k=top_k)
        retrieved_ids = [str(item.get("chunk_id")) for item in retrieved]
        row = {
            "id": question.get("id"),
            "question": question.get("question", ""),
            "answerable": True,
            "expected_chunk_ids": expected,
            "retrieved_chunk_ids": retrieved_ids,
            "retrieved": [{"chunk_id": item.get("chunk_id"), "score": item.get("score"), "heading_path": item.get("heading_path"), "page_start": item.get("page_start"), "page_end": item.get("page_end")} for item in retrieved],
            "hit_at_1": hit_at_k(retrieved_ids, expected, 1) if expected else None,
            "hit_at_3": hit_at_k(retrieved_ids, expected, 3) if expected else None,
            "hit_at_5": hit_at_k(retrieved_ids, expected, 5) if expected else None,
            "precision_at_5": precision_at_k(retrieved_ids, expected, min(5, top_k)) if expected else None,
            "mrr": reciprocal_rank(retrieved_ids, expected) if expected else None,
        }
        rows.append(row)
        if expected:
            answerable_rows.append(row)
    denom = len(answerable_rows) or 1
    summary = {
        "questions": len(questions),
        "answerable_questions": len(answerable_rows),
        "top_k": top_k,
        "recall_at_1": round(sum(row["hit_at_1"] for row in answerable_rows) / denom, 6),
        "recall_at_3": round(sum(row["hit_at_3"] for row in answerable_rows) / denom, 6),
        f"recall_at_{top_k}": round(sum(hit_at_k(row["retrieved_chunk_ids"], row["expected_chunk_ids"], top_k) for row in answerable_rows) / denom, 6),
        "recall_at_5": round(sum(row["hit_at_5"] for row in answerable_rows) / denom, 6),
        "precision_at_5": round(sum(row["precision_at_5"] for row in answerable_rows) / denom, 6),
        "mrr": round(sum(row["mrr"] for row in answerable_rows) / denom, 6),
    }
    run_path = project / "eval/runs" / f"{run_id}-retrieval.jsonl"
    report_path = project / "eval/reports" / f"{run_id}-retrieval.md"
    write_jsonl(run_path, rows)
    report_path.write_text(render_retrieval_report(project, run_id, summary, rows), encoding="utf-8")
    return {"run_id": run_id, "summary": summary, "run_path": str(run_path), "report_path": str(report_path), "rows": rows}


def render_retrieval_report(project: Path, run_id: str, summary: dict, rows: Sequence[dict]) -> str:
    lines = [
        "# Retrieval Evaluation Report",
        "",
        f"- Project: `{project}`",
        f"- Run ID: `{run_id}`",
        "",
        "## Summary",
        "",
        "| Metric | Score |",
        "|---|---:|",
    ]
    for key in ("questions", "answerable_questions", "top_k", "recall_at_1", "recall_at_3", "recall_at_5", "mrr", "precision_at_5"):
        if key in summary:
            lines.append(f"| {key} | {summary[key]} |")
    failures = [row for row in rows if row.get("answerable", True) and row.get("expected_chunk_ids") and not hit_at_k(row.get("retrieved_chunk_ids", []), row.get("expected_chunk_ids", []), 5)]
    lines += ["", "## Retrieval Failures", ""]
    if not failures:
        lines.append("No Recall@5 failures.")
    else:
        lines += ["| ID | Question | Expected | Retrieved |", "|---|---|---|---|"]
        for row in failures:
            q = str(row.get("question", "")).replace("|", "\\|")
            lines.append(f"| {row.get('id')} | {q} | {', '.join(row.get('expected_chunk_ids', []))} | {', '.join(row.get('retrieved_chunk_ids', []))} |")
    lines.append("")
    return "\n".join(lines)


def refusal_detected(answer: str) -> bool:
    patterns = ["確認できません", "分かりません", "わかりません", "本の資料からは", "資料からは", "not found", "not supported", "cannot determine"]
    lowered = answer.lower()
    return any(pattern.lower() in lowered for pattern in patterns)


def evaluate_answer_records(questions: Sequence[dict], answers: Sequence[dict], *, valid_chunk_ids: set[str]) -> dict:
    by_id = {str(item.get("id")): item for item in questions}
    rows: list[dict] = []
    point_scores: list[float] = []
    citation_scores: list[float] = []
    unanswerable_scores: list[float] = []
    for answer_record in answers:
        qid = str(answer_record.get("question_id") or answer_record.get("id"))
        question = by_id.get(qid, {})
        answer = str(answer_record.get("answer", ""))
        citations = [str(c) for c in answer_record.get("citations", [])]
        expected_points = [str(p) for p in question.get("expected_answer_points") or []]
        if expected_points:
            point_score = sum(1 for point in expected_points if point.lower() in answer.lower()) / len(expected_points)
            point_scores.append(point_score)
        else:
            point_score = None
        if citations:
            citation_validity = sum(1 for c in citations if c in valid_chunk_ids) / len(citations)
            citation_scores.append(citation_validity)
        elif question.get("must_cite"):
            citation_validity = 0.0
            citation_scores.append(0.0)
        else:
            citation_validity = None
        if not question.get("answerable", True):
            unanswerable = 1.0 if refusal_detected(answer) else 0.0
            unanswerable_scores.append(unanswerable)
        else:
            unanswerable = None
        rows.append({"question_id": qid, "answer_point_coverage": point_score, "citation_validity": citation_validity, "unanswerable_correct": unanswerable})
    summary = {
        "answers": len(answers),
        "answer_point_coverage": round(sum(point_scores) / len(point_scores), 6) if point_scores else None,
        "citation_validity": round(sum(citation_scores) / len(citation_scores), 6) if citation_scores else None,
        "unanswerable_accuracy": round(sum(unanswerable_scores) / len(unanswerable_scores), 6) if unanswerable_scores else None,
    }
    return {"summary": summary, "rows": rows}


def evaluate_answers(project: Path, answers_path: Path, *, run_id: str | None = None) -> dict:
    run_id = run_id or time.strftime("%Y%m%d-%H%M%S")
    init_eval_files(project)
    questions = read_jsonl(project / "eval/golden-questions.jsonl")
    answers = read_jsonl(answers_path)
    valid_chunk_ids = {str(c.get("chunk_id")) for c in read_jsonl(project / "index/chunks.jsonl") if c.get("chunk_id")}
    result = evaluate_answer_records(questions, answers, valid_chunk_ids=valid_chunk_ids)
    run_path = project / "eval/runs" / f"{run_id}-answers.jsonl"
    report_path = project / "eval/reports" / f"{run_id}-answers.md"
    write_jsonl(run_path, result["rows"])
    report_path.write_text(render_answer_report(project, run_id, result["summary"], result["rows"]), encoding="utf-8")
    return {"run_id": run_id, "summary": result["summary"], "run_path": str(run_path), "report_path": str(report_path), "rows": result["rows"]}


def render_answer_report(project: Path, run_id: str, summary: dict, rows: Sequence[dict]) -> str:
    lines = ["# Answer Evaluation Report", "", f"- Project: `{project}`", f"- Run ID: `{run_id}`", "", "## Summary", "", "| Metric | Score |", "|---|---:|"]
    for key, value in summary.items():
        lines.append(f"| {key} | {value} |")
    lines += ["", "## Rows", "", "| Question | Points | Citation validity | Unanswerable |", "|---|---:|---:|---:|"]
    for row in rows:
        lines.append(f"| {row.get('question_id')} | {row.get('answer_point_coverage')} | {row.get('citation_validity')} | {row.get('unanswerable_correct')} |")
    lines.append("")
    return "\n".join(lines)


def cmd_init(args: argparse.Namespace) -> None:
    init_book_project(Path(args.project), BookMetadata(args.title, args.author, args.language, args.book_id))
    print(f"initialized {args.project}")


def cmd_ingest(args: argparse.Namespace) -> None:
    project = Path(args.project)
    meta = BookMetadata(args.title or project.name, args.author, args.language, args.book_id)
    init_book_project(project, meta, overwrite_metadata=True)
    source = Path(args.source)
    target_source = project / "source" / source.name
    if source.resolve() != target_source.resolve():
        shutil.copyfile(source, target_source)
    extract_text_or_markdown(target_source, project / "extracted/full.md")
    stats = build_indexes(project, max_chars=args.max_chars, overlap_chars=args.overlap_chars)
    print(json.dumps({"project": str(project), **stats, **validate_project(project)}, ensure_ascii=False, indent=2))


def cmd_index(args: argparse.Namespace) -> None:
    stats = build_indexes(Path(args.project), max_chars=args.max_chars, overlap_chars=args.overlap_chars)
    print(json.dumps(stats, ensure_ascii=False, indent=2))


def cmd_validate(args: argparse.Namespace) -> None:
    print(json.dumps(validate_project(Path(args.project)), ensure_ascii=False, indent=2))


def cmd_eval_init(args: argparse.Namespace) -> None:
    result = init_eval_files(Path(args.project), overwrite_template=args.overwrite)
    print(json.dumps(result, ensure_ascii=False, indent=2))


def cmd_eval_retrieval(args: argparse.Namespace) -> None:
    result = evaluate_retrieval(Path(args.project), top_k=args.top_k, run_id=args.run_id)
    printable = {k: v for k, v in result.items() if k != "rows"}
    print(json.dumps(printable, ensure_ascii=False, indent=2))


def cmd_eval_answers(args: argparse.Namespace) -> None:
    result = evaluate_answers(Path(args.project), Path(args.answers), run_id=args.run_id)
    printable = {k: v for k, v in result.items() if k != "rows"}
    print(json.dumps(printable, ensure_ascii=False, indent=2))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Create Hermes-friendly book ingestion projects")
    sub = parser.add_subparsers(required=True)

    p_init = sub.add_parser("init", help="Create an empty book project")
    p_init.add_argument("project")
    p_init.add_argument("--title", required=True)
    p_init.add_argument("--author", default="Unknown")
    p_init.add_argument("--language", default="ja")
    p_init.add_argument("--book-id")
    p_init.set_defaults(func=cmd_init)

    p_ingest = sub.add_parser("ingest", help="Copy source, extract text, and build indexes")
    p_ingest.add_argument("source")
    p_ingest.add_argument("project")
    p_ingest.add_argument("--title")
    p_ingest.add_argument("--author", default="Unknown")
    p_ingest.add_argument("--language", default="ja")
    p_ingest.add_argument("--book-id")
    p_ingest.add_argument("--max-chars", type=int, default=3200)
    p_ingest.add_argument("--overlap-chars", type=int, default=250)
    p_ingest.set_defaults(func=cmd_ingest)

    p_index = sub.add_parser("index", help="Rebuild indexes from extracted/full.md")
    p_index.add_argument("project")
    p_index.add_argument("--max-chars", type=int, default=3200)
    p_index.add_argument("--overlap-chars", type=int, default=250)
    p_index.set_defaults(func=cmd_index)

    p_validate = sub.add_parser("validate", help="Validate generated project artifacts")
    p_validate.add_argument("project")
    p_validate.set_defaults(func=cmd_validate)

    p_eval_init = sub.add_parser("eval-init", help="Create evaluation templates, runs/reports dirs, and judge prompts")
    p_eval_init.add_argument("project")
    p_eval_init.add_argument("--overwrite", action="store_true", help="Overwrite existing eval templates/prompts")
    p_eval_init.set_defaults(func=cmd_eval_init)

    p_eval_retrieval = sub.add_parser("eval-retrieval", help="Evaluate lexical retrieval against eval/golden-questions.jsonl")
    p_eval_retrieval.add_argument("project")
    p_eval_retrieval.add_argument("--top-k", type=int, default=5)
    p_eval_retrieval.add_argument("--run-id")
    p_eval_retrieval.set_defaults(func=cmd_eval_retrieval)

    p_eval_answers = sub.add_parser("eval-answers", help="Evaluate deterministic answer/citation/refusal checks from an answers JSONL")
    p_eval_answers.add_argument("project")
    p_eval_answers.add_argument("--answers", required=True, help="JSONL with question_id, answer, citations")
    p_eval_answers.add_argument("--run-id")
    p_eval_answers.set_defaults(func=cmd_eval_answers)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
