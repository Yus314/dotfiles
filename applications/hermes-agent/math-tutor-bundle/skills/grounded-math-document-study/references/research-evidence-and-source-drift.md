# Research evidence and source-drift procedure

## Condensed evidence bank

These results motivate the skill's hybrid architecture. Verify current versions before quoting exact leaderboard values.

### Long context is not uniform usable context

- **Lost in the Middle** — relevant information is often used less reliably in the middle of long inputs.
  - https://arxiv.org/abs/2307.03172
- **RULER** — simple needle retrieval can remain strong while multi-needle, tracing, aggregation, and QA degrade with length.
  - https://arxiv.org/abs/2404.06654
- **InfiniteBench** — passkey retrieval and realistic long QA/code/mathematical aggregation show large capability gaps.
  - https://arxiv.org/abs/2402.13718
- **NoLiMa** — reducing lexical overlap between question and evidence sharply weakens many long-context models.
  - https://arxiv.org/abs/2502.05167
- **MathHay** — finding numerical evidence and reasoning over it are separate bottlenecks; it is not a benchmark of abstract proof reconstruction.
  - https://arxiv.org/abs/2410.04698

Inference: use whole-context input as an overview/baseline, not the sole trusted reading path.

### PDF parsing and multimodal retrieval are separate problems

- **OmniDocBench** separates text, layout, reading order, table, and formula quality.
  - https://openaccess.thecvf.com/content/CVPR2025/html/Ouyang_OmniDocBench_Benchmarking_Diverse_PDF_Document_Parsing_with_Comprehensive_Annotations_CVPR_2025_paper.html
- **MPDocBench-Parse** adds multi-page continuity, hierarchy, and page-boundary merging; current status is preprint.
  - https://arxiv.org/abs/2605.22100
- **MMLongBench-Doc** shows that all-page image input still suffers from localization, perception, and cross-page integration failures.
  - https://arxiv.org/abs/2407.01523
- **ColPali / VisRAG / MMDocIR** show the value of page-image retrieval for layout, tables, figures, and OCR-loss cases.
  - https://arxiv.org/abs/2407.01449
  - https://arxiv.org/abs/2410.10594
  - https://arxiv.org/abs/2501.08828

Inference: preserve structured text and page images; use each for what it is good at.

### Structure, hierarchy, and evidence matter

- **PDFTriage** exposes page/section/table/figure structure as reading tools.
  - https://aclanthology.org/2024.emnlp-industry.13/
- **Late Chunking** preserves surrounding context in chunk representations; overlap alone is not a universal fix.
  - https://arxiv.org/abs/2409.04701
- **RAPTOR / GraphRAG** improve global or multi-level sensemaking but summaries remain lossy derived artifacts.
  - https://arxiv.org/abs/2401.18059
  - https://arxiv.org/abs/2404.16130
- **DocScope** separates page localization, region grounding, fact extraction, and final answer; current status is preprint.
  - https://arxiv.org/abs/2605.08888

Inference: maps guide navigation; exact claims return to source pages. Correct-looking answers do not prove correct evidence chains.

## Source drift: durable procedure

Public PDFs can be silently regenerated while the visible website date remains stale. A filename such as `Book4e.pdf` is not an identity.

### Inventory

Collect all plausible copies:

- the configured canonical artifact;
- copies in Downloads or old projects;
- a fresh official download.

For each record:

- absolute path;
- official source URL;
- SHA-256 and byte size;
- PDF page count;
- embedded creation/modification metadata;
- printed revision/date where present.

If an artifact-root environment variable is unset, inspect project documentation for the default root before declaring the source unavailable.

### Compare differing hashes

Hash mismatch means “not byte-identical,” not “different pagination” or “different mathematical content.” Compare in layers:

1. page count;
2. whole-book extracted-text hash;
3. page-level extracted-text hashes;
4. unified diffs for changed pages;
5. high-DPI render spot checks for changed mathematical pages.

Deterministic page-text probe:

```python
from pypdf import PdfReader
import hashlib

pages = [(page.extract_text() or "") for page in PdfReader(path).pages]
book_hash = hashlib.sha256("\f".join(pages).encode()).hexdigest()
page_hashes = [hashlib.sha256(text.encode()).hexdigest() for text in pages]
```

Use the differing page indices to constrain manual inspection. State conclusions narrowly:

- “text differences were detected on pages X–Y” is supported;
- “pagination did not change in inspected text” may be supported;
- “the PDFs are fully mathematically equivalent” is not supported without exhaustive visual/semantic checks.

### Publish a new canonical revision

1. Archive the old canonical file under a revisioned path.
2. Copy the new file to a staging path inside the destination directory.
3. Atomically rename/replace staging to canonical.
4. Recompute canonical hash, size, page count, and embedded revision from the installed file.
5. Update book metadata with previous-version provenance.
6. Delete only temporary downloads, not archived canonical revisions.
7. Rebuild or invalidate all derived objects whose `source_sha256` no longer matches.

### Metadata fields

Recommended book metadata:

```yaml
pdf_local:
pdf_source_url:
pdf_sha256:
pdf_md5:          # optional; SHA-256 remains primary
pdf_size_bytes:
pdf_pages:
pdf_revision:
pdf_identity_verified:
previous_pdf:
previous_pdf_sha256:
printed_page_mapping_status:
```

Every manifest/index should carry `source_id` and `source_sha256`. Fail closed on mixed-source pages.

## Formula handling

For high-value formulas, preserve three views:

- source crop image;
- LaTeX/MathML candidate;
- normalized retrieval form.

Check distinctions such as scripts, bars, stars, bold/script fonts, strict/non-strict inclusion, signs, quantifiers, and matrix boundaries. Rendering a candidate formula and comparing it to the source image is stronger than trusting string output alone, but does not by itself prove semantic equivalence.

## Small gold set before complex infrastructure

Include:

- exact definition and theorem statements;
- theorem/exercise ID lookup;
- notation disambiguation;
- proof boundary and hypothesis use;
- exact formula checks;
- cross-page references;
- global chapter synthesis;
- unsupported/unanswerable questions;
- edition and page citation checks.

Keep extraction, retrieval, generation, citation, evidence-chain, and learning outcomes as distinct layers. A complete ingestion pipeline is infrastructure, not proof that the learner understands the mathematics.
