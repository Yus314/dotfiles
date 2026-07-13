#!/usr/bin/env python3
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "book_ingest.py"
SPEC = importlib.util.spec_from_file_location("book_ingest", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load {SCRIPT}")
book_ingest = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = book_ingest
SPEC.loader.exec_module(book_ingest)


class BookIngestTests(unittest.TestCase):
    def test_long_single_paragraph_respects_max_chars(self):
        chunks = list(book_ingest._split_text_with_overlap("x" * 10_000, 1_000, 100))
        self.assertGreater(len(chunks), 1)
        self.assertTrue(all(0 < len(text) <= 1_000 for _, _, text in chunks))

    def test_invalid_chunk_parameters_fail(self):
        with self.assertRaises(ValueError):
            list(book_ingest._split_text_with_overlap("abc", 0, 0))
        with self.assertRaises(ValueError):
            list(book_ingest._split_text_with_overlap("abc", 10, 10))

    def test_chapter_files_include_subheadings_and_remove_stale_files(self):
        markdown = "# Book\n\nIntro\n\n## Chapter 1\n\nBody\n\n### Detail\n\nSub-body\n\n## Chapter 2\n\nNext\n"
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            stale = project / "extracted/chapters/ch99-stale.md"
            stale.parent.mkdir(parents=True)
            stale.write_text("stale")
            (project / "index").mkdir(parents=True)
            book_ingest.write_toc_and_chapters(project, markdown)
            chapter_one = next((project / "extracted/chapters").glob("*-chapter-1.md"))
            text = chapter_one.read_text()
            self.assertIn("### Detail", text)
            self.assertIn("Sub-body", text)
            self.assertNotIn("## Chapter 2", text)
            self.assertFalse(stale.exists())

    def test_reingest_metadata_overwrites_manifest_and_agents(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            old = book_ingest.BookMetadata("Old title", "Old author", book_id="old")
            new = book_ingest.BookMetadata("New title", "New author", book_id="new")
            book_ingest.init_book_project(project, old)
            book_ingest.init_book_project(project, new, overwrite_metadata=True)
            manifest = json.loads((project / "index/manifest.json").read_text())
            self.assertEqual(manifest["book_id"], "new")
            self.assertEqual(manifest["title"], "New title")
            self.assertIn("New title", (project / "AGENTS.md").read_text())


if __name__ == "__main__":
    unittest.main()
