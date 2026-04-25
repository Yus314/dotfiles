---
name: codex
description: Use when the user asks to run Codex CLI (codex exec, codex resume) or references OpenAI Codex for code analysis, refactoring, or automated editing
---

# Codex Skill Guide

## Running a Task
1. If the user specifies a model, use it. Otherwise prefer the Codex CLI default model instead of hardcoding model choices in this skill.
2. If the user specifies a reasoning effort, pass it with `--config model_reasoning_effort="<xhigh|high|medium|low>"`. Otherwise use the CLI or profile default. Only force a higher reasoning effort when the task genuinely needs deeper analysis.
3. Select the execution mode required for the task:
   - Use `--sandbox read-only` for read-only review or analysis.
   - Use `--full-auto` when Claude is delegating substantive implementation or exploration to Codex and approval friction should stay low. `--full-auto` implies `--sandbox workspace-write` and `-a on-request`.
   - Use `--sandbox danger-full-access` only when the task truly requires broader access.
4. Assemble the command with the appropriate options:
   - `-m, --model <MODEL>`
   - `--config model_reasoning_effort="<xhigh|high|medium|low>"`
   - `-a, --ask-for-approval <untrusted|on-request|never>`
   - `--sandbox <read-only|workspace-write|danger-full-access>`
   - `--full-auto`
   - `-C, --cd <DIR>`
   - `--skip-git-repo-check`
5. Only add `--skip-git-repo-check` when the task must run outside a Git repository or when Claude is intentionally using Codex for Git-unaware analysis. Do not treat it as a mandatory default.
6. When continuing a previous session, prefer `codex exec resume --last` and preserve the existing session settings unless there is a concrete reason to override them. Overriding model, approval, or sandbox settings during resume is allowed when the task has changed.
7. Do not suppress stderr by default. Keep warnings and execution diagnostics visible unless there is a specific reason to reduce noise, and summarize any meaningful warnings for the user.
8. Run the command, capture stdout/stderr, and summarize the outcome for the user.
9. After Codex completes, mention that the session can be resumed later with `codex resume` or by asking Claude to continue the existing Codex work.

### Quick Reference
| Use case | Approval | Sandbox mode | Example |
| --- | --- | --- | --- |
| Read-only review or analysis | Default or explicit `untrusted` | `read-only` | `codex exec --sandbox read-only "review this code for bugs"` |
| Delegate edits with low friction | `on-request` via `--full-auto` | `workspace-write` via `--full-auto` | `codex exec --full-auto "implement the requested change"` |
| Permit broad local or network access | Match task risk explicitly | `danger-full-access` | `codex exec -a on-request --sandbox danger-full-access "investigate and fix the issue"` |
| Resume recent session | Usually inherit existing session policy | Usually inherit existing session policy | `codex exec resume --last "continue from the prior findings"` |
| Run outside a Git repo | Match task needs | Match task needs | `codex exec --sandbox read-only --skip-git-repo-check "analyze these files"` |
| Run from another directory | Match task needs | Match task needs | `codex exec -C <DIR> --full-auto "work on this project"` |

## Following Up
- Use `AskUserQuestion` when there is a real branching choice to make, such as selecting a follow-up direction or clarifying whether Codex should resume with broader permissions.
- When resuming, either pass the new prompt as an argument or via stdin: `codex exec resume --last "continue"` or `echo "continue" | codex exec resume --last -`.
- Restate the chosen model, reasoning effort, and execution mode when proposing follow-up actions if those details matter to the next step.

## Critical Evaluation of Codex Output

Codex is powered by OpenAI models with their own knowledge cutoffs and limitations. Treat Codex as a **colleague, not an authority**.

### Guidelines
- **Trust your own knowledge** when confident. If Codex claims something you know is incorrect, push back directly.
- **Research disagreements** using WebSearch or documentation before accepting Codex's claims. Share findings with Codex via resume if needed.
- **Remember knowledge cutoffs** - Codex may not know about recent releases, APIs, or changes that occurred after its training data.
- **Don't defer blindly** - Codex can be wrong. Evaluate its suggestions critically, especially regarding:
  - Model names and capabilities
  - Recent library versions or API changes
  - Best practices that may have evolved

### When Codex is Wrong
1. State your disagreement clearly to the user
2. Provide evidence (your own knowledge, web search, docs)
3. Optionally resume the Codex session to discuss the disagreement. **Identify yourself as Claude** so Codex knows it's a peer AI discussion. Use your actual model name (e.g., the model you are currently running as) instead of a hardcoded name:
   ```bash
   echo "This is Claude (<your current model name>) following up. I disagree with [X] because [evidence]. What's your take on this?" | codex exec --skip-git-repo-check resume --last -
   ```
4. Frame disagreements as discussions, not corrections - either AI could be wrong
5. Let the user decide how to proceed if there's genuine ambiguity

## Error Handling
- Stop and report failures whenever `codex --version` or a `codex exec` command exits non-zero; request direction before retrying.
- Before you use high-impact flags (`--full-auto`, `--sandbox danger-full-access`, `--skip-git-repo-check`) ask the user for permission using AskUserQuestion unless it was already given.
- When output includes warnings or partial results, summarize them and ask how to adjust using `AskUserQuestion`.
