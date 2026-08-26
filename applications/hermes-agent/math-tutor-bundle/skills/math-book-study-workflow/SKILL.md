---
name: math-book-study-workflow
description: Use when adding a new mathematics textbook to study_log or running a NotebookLM/OpenAI-Pro plus Hermes workflow for proof-based math study. Creates book metadata, note templates, AI-draft intake, overview maps, key-result spines, Socratic exercise sessions, and review logs.
version: 1.1.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [math, study-log, textbooks, socratic, openai-pro, notebooklm]
    related_skills: [grounded-math-document-study, cross-machine-study-environments]
---

# Math Book Study Workflow

## Overview

Use this workflow to apply the LADR-style `study_log` system to any proof-based mathematics textbook. The core pattern is:

```text
OpenAI Pro / NotebookLM-style PDF reading
  → Hermes compresses output into study_log maps
  → daily exercises are handled through Socratic dialogue
  → understanding changes, confusion, and review targets are logged
```

The goal is not to build a polished AI-generated textbook summary. The goal is to create a reusable learning operating system: global map, chapter map, key results, notation index, confusion log, and exercise dialogue logs.

## Hermes profile separation

When mathematics study becomes a long-running workflow, consider separating it into a dedicated Hermes profile such as `math`. Keep the shared repository at `~/study_log`, use `~/study_log/math` as the canonical mathematics root, and separate Hermes memory, sessions, skills, SOUL/persona, and cron so Socratic proof-learning norms do not mix with the general personal-assistant profile.

See `references/hermes-math-profile.md` for the setup and verification checklist, including profile-local Honcho/memory checks and pitfalls.

For recurring PDF-grounded study, source-version integrity, OCR-versus-vision routing, retrieval evaluation, and delayed learning tests, see `references/pdf-grounded-study-evaluation.md`.

## When to Use

Use when the user says things like:

- "新しい数学書を study_log に追加したい"
- "この本でも LADR と同じ仕組みを使いたい"
- "OpenAI Pro / NotebookLM で全体構造を抽出したので整理して"
- "この数学書の学習ログを作って"
- "演習を解きながら理解を深めたい"

Do not use for one-off math questions where no persistent book workflow is needed.

## Directory Convention

Expected root:

```text
~/study_log/math/
├── books/
│   ├── _template.md
│   └── [book_id].md
└── notes/
    ├── _template/
    │   ├── README.md
    │   ├── book-overview.md
    │   ├── key-results-spine.md
    │   ├── chN-overview.md
    │   └── notation-index.md
    └── [book_id]/
        ├── README.md
        ├── book-ai-draft.md
        ├── book-overview.md
        ├── key-results-spine.md
        ├── notation-index.md
        ├── ch1-overview.md
        ├── ch1-exercises.md
        └── ch1-confusion.md
```

## Step 1: Register the Book

Ask for or infer:

```text
book_id:
title:
author:
edition:
field:
level:
pdf path or URL:
why study this book:
```

For a local PDF, also record its canonical path, SHA-256, byte size, PDF page count, and whether printed-page mapping is verified or inferred. Label the hash algorithm correctly. If the source is later replaced or corrected, compare hash and page count before reusing old indexes or page citations; rebuild or establish an explicit page map when they differ.

Create:

- `books/[book_id].md` from `books/_template.md`
- `notes/[book_id]/README.md` from `notes/_template/README.md`
- `notes/[book_id]/notation-index.md` from `notes/_template/notation-index.md`

Use lowercase, short, stable `book_id` values, e.g. `ladr`, `munkres_topology`, `baby_rudin`.

## Step 2: Generate the OpenAI Pro Prompt

Give the user this prompt to paste into ChatGPT Pro / Project / NotebookLM-style environment:

```text
対象PDFは [Book Title] として扱います。
この本全体を、数学学習者向けに以下の観点で整理してください。

1. 本全体の目的・設計思想
2. 全体の章構成と概念の流れ
3. 各章の役割
4. 各章が前の章から何を受け継ぐか
5. 各章が後の章へ何を渡すか
6. 主要定義・主要定理・主要命題
7. 初学者が詰まりやすい概念
8. 演習で鍛えるべき力
9. 学習上の背骨になる定理・命題 5-15 個
10. 章ごとの推奨学習順序

可能なら、章・節・定理番号・ページを明記してください。
「原文に基づく情報」と「学習者向け解釈」を区別してください。
推測は推測と明記してください。
```

## Step 3: Intake OpenAI Pro Output

When the user pastes the output:

1. Save raw text to `notes/[book_id]/book-ai-draft.md`.
2. Create a compressed operational map at `notes/[book_id]/book-overview.md`.
3. Extract 5-15 central results into `notes/[book_id]/key-results-spine.md`.
4. Mark verification state as `verified: false` or `verified: partially`.
5. Do not copy the full AI text into session logs.

Operational map sections:

- How to use this file
- Big design of the book
- Overall conceptual flow
- Key-result spine
- Chapter-by-chapter roles
- Common confusions
- What exercises train
- Suggested learning order

## Step 4: Prepare Chapter 1

Ask OpenAI Pro or use provided output to create:

- `notes/[book_id]/ch1-overview.md`
- optionally `ch1-exercises.md`
- optionally `ch1-confusion.md`

Chapter overview should include:

- chapter role
- section structure
- key definitions/results/examples
- downstream connections
- common confusions
- skills trained
- Socratic questions
- first small tasks
- log prompts

## Step 5: Run Socratic Exercise Sessions

When solving exercises, require the user’s attempt first unless they explicitly ask for a direct explanation.

When Lean/Mathlib is used as a checker, keep mathematical hints and Lean/API hints in visibly separate tracks. Verify the exact book statement first, create only a type-checked statement scaffold before the learner’s attempt, and distinguish `source verified`, `statement compiled`, `proof compiled`, and `code-free reconstruction`. See `references/lean-assisted-proof-exercises.md` for the full protocol and coordinate-space encoding pattern.

User template:

```text
[Book] Chapter/Section/Exercise をやります。
すぐ答えず、Socraticに質問してください。

問題文:
自分の考え:
詰まっている点:
使えそうな定義・定理:
```

Hint ladder:

1. Restate the problem.
2. Separate assumptions and conclusion.
3. Ask for a small example/non-example.
4. Recall relevant definitions/results.
5. Offer a strategy hint.
6. Offer one local next step.
7. Give proof skeleton.
8. Give full solution only after sufficient attempt or explicit request.
9. Ask user to reconstruct the solution.

## Step 6: Log Understanding Changes

Session logs should capture understanding changes, not polished AI output.

Minimal log:

```md
## 今日の数学対話
- 扱った対象:
- 最初の考え:
- 詰まり:
- 気づき:
- 未解決:
- 次回:
```

Exercise log:

```md
### Exercise X.Y
- 自力試行:
- 詰まり:
- 使った定義・定理:
- 有効だったヒント:
- 最終理解:
- 再訪:
```

Unresolved issues go into `notes/[book_id]/chN-confusion.md`.

After any substantive tutoring conversation, verify that the durable ledger reflects the actual learning delta. A session that exists only in chat while the study file remains an empty template is not recorded progress. Keep the write small: object studied, initial misconception, hint level, corrected reconstruction, confidence, source page, and next review date. Do not auto-write a polished narrative.

Schedule or prompt changed-form retrieval rather than merely repeating the answer: immediate reconstruction, roughly 1-day rewording, roughly 3-day example/non-example or proof skeleton, and roughly 7-day transfer. Treat ingestion completeness and AI-generated maps as infrastructure, not evidence of learner mastery.

## Step 7: Weekly Review

Review:

- definitions/results encountered
- exercises attempted
- hint-dependent solutions
- unresolved confusion
- key-result spine progress
- revisit items
- next week’s WOOP

Avoid Goodhart metrics: do not optimize for pages, hours, or streaks. Prefer explainability, example generation, proof reconstruction, and calibrated confidence.

## Hermes Profile Separation for Math Study

When the user asks whether to isolate mathematics learning in Hermes, prefer a staged `math` profile design rather than mixing deep math tutoring into the default personal-secretary profile.

Recommended pattern:

1. Keep `~/study_log` as the shared repository and `~/study_log/math` as the canonical mathematics root; do not duplicate the mathematics record per profile.
2. Use a dedicated Hermes profile such as `math` for Socratic mathematics conversations, proof reconstruction, confusion review, and structural edits to `~/study_log/math`.
3. Set the math profile's default workspace to `~/study_log/math` when configuring it, e.g. `hermes -p math config set terminal.cwd /home/kaki/study_log/math`.
4. Give the math profile a mathematics-specific `SOUL.md`: protect productive failure, ask for attempts before full solutions, use examples/non-examples, avoid Goodhart metrics, and log understanding changes rather than polished AI summaries.
5. Leave the default profile as the general personal secretary for calendar, diary, tasks, finance, and PC/file help. It may read or summarize math context, but deep math dialogue and study_log edits should belong to the math profile.
6. Do not start by splitting the messaging gateway unless the user explicitly wants a separate Discord/Telegram math bot. First validate the profile via CLI or explicit `hermes -p math ...` usage; add gateway separation later if the workflow sticks.
7. Remember that Hermes profiles separate config, memory, sessions, skills, cron jobs, and gateway state, but they are not filesystem sandboxes on the local terminal backend.

## Profile Separation for Mathematics Study

When the user wants mathematics learning separated from their general Hermes assistant, prefer a staged `math` profile rollout instead of immediately wiring a new gateway bot.

Recommended sequence:

1. Create or reuse a `math` profile and use `~/study_log/math` as its canonical mathematics root within the shared `~/study_log` repository.
2. Set the math profile's default workspace toward `~/study_log/math` where supported, but verify with an actual `pwd` from inside a math-profile session; config display and tool execution can diverge in nested/gateway contexts.
3. Put Socratic mathematics behavior in the math profile's `SOUL.md`: proof-based coaching, no full solutions before attempt unless requested, productive-failure protection, confusion logging, and Goodhart-metric avoidance.
4. Start with the reviewed minimal profile allowlist: `math-book-study-workflow`, `grounded-math-document-study`, and `cross-machine-study-environments`. Add document or research helpers only after a concrete workflow requires them and the bundle manifest is reviewed.
5. Keep the default profile as the general personal secretary; let the math profile own deep math conversations and structural edits to `~/study_log/math`.
6. Defer Discord/gateway separation until the CLI/profile workflow has been used successfully a few times.

Verification checklist for the separated profile:

- `hermes profile show math` reports the intended model and profile path.
- `hermes -p math skills list` shows the math-study skills enabled.
- `hermes -p math doctor` has no blockers for the intended usage.
- A short `hermes -p math chat -q ...` smoke test shows the math persona is active.
- If workspace matters, ask the profile to run `pwd`; do not rely only on `hermes -p math config` output.

## Common Pitfalls

1. **Assuming profile separation is a sandbox.** Hermes profiles separate config, sessions, memory, skills, cron, and gateway state, but on a local terminal backend they do not restrict filesystem access. Keep `~/study_log` as the shared record and define editing ownership by convention.
2. **Moving straight to gateway separation.** A separate Discord bot/profile is useful later, but first validate the math profile from CLI or explicit `hermes -p math` runs.
3. **AI summary replaces learning.** Use AI maps as maps, not as understanding.
2. **Raw AI output pollutes study_log.** Keep raw output in `book-ai-draft.md`; session logs should be personal understanding.
3. **No verification state.** AI page numbers and theorem numbers can be wrong; mark `verified` status.
4. **Too many cards.** Do not card every theorem. Select key results.
5. **Skipping examples/non-examples.** Definitions in proof-based math need examples and boundary cases.
6. **Giving full answers too early.** Preserve productive failure with a hint ladder.
7. **Treating source, search index, and page images as independent files.** For recurring PDF study, bind derived artifacts to a canonical source ID/hash, use hybrid Japanese retrieval rather than unicode61 alone, and follow `references/pdf-grounded-study-evaluation.md` for provenance and evaluation semantics.
8. **Reporting a stale green checkpoint.** Any fix made after tests or an independent audit invalidates that completion claim until the full quality gate is rerun.

## Verification Checklist

- [ ] `books/[book_id].md` exists
- [ ] `notes/[book_id]/README.md` exists
- [ ] Raw AI output is saved separately as `book-ai-draft.md`
- [ ] `book-overview.md` is concise and operational
- [ ] `key-results-spine.md` has 5-15 results
- [ ] Chapter 1 has an overview with Socratic questions
- [ ] Session logs record understanding changes, not AI summaries
- [ ] Unresolved confusion has a durable place
