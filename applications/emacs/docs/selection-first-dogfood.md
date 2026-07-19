# Selection-first dogfood runbook

This trial uses a separately named Emacs daemon. It does not replace the normal
Home Manager generation or production Emacs service.

## Connect

The current local launchers are:

```bash
~/.local/state/selection-dogfood/start   # start or report already running
~/.local/state/selection-dogfood/client  # open a GUI client
~/.local/state/selection-dogfood/stop    # stop only this named daemon
```

The client launcher connects to server `selection-dogfood`. The production
server remains available through the ordinary `emacsclient` command.

## Scope

Run for 2–3 working days and record at least:

- 30 editing episodes;
- 10 plural-selection episodes;
- 5 plural `i`/`a` batch-insert episodes, including one Japanese committed
  string, Return, backward/forward deletion, unsupported-key rejection, and
  per-intent undo across the set;
- 5 prompt cancellation or native-handoff episodes;
- one named-daemon restart and several client reconnects.

An episode is one editing intention ending in success, designed rejection,
fallback, or failure. It is not one key press.

Cover plain text, Org, programming buffers, Japanese text, narrowing, multiple
windows, buffer kill/switch, native `:`/`M-x` handoff, prompt `C-g`, undo, and
rejection in read-only or special buffers.

For batch-insert, verify that `Sel BI:<count>` is visible, Escape preserves the
plural carets, unsupported commands change no text, and each undo removes one
committed intent from every caret. IME preedit, CAPF, snippets, electric-pair,
auto-fill, and abbrev are outside the MVP; record the need as a missing adapter
rather than treating primary-only fallback as acceptable.

## Privacy-safe log

Append one row per episode to:

```text
~/.local/state/selection-dogfood/episodes.tsv
```

Allowed columns are day, coarse time bucket, mode class, selection-count bucket,
operation category, result, latency class, fallback, undo result, and a sanitized
error category. Never record buffer text, selected/replacement text, filenames,
projects, paths, positions, ranges, minibuffer input, kill-ring/register values,
LSP payloads, hashes of selected text, or personal-buffer backtraces.

For diagnosis, first reproduce the failure in a synthetic buffer with invented
content; capture detailed traces only from that reproduction.

Use the local enum-only logger instead of editing the TSV directly:

```bash
~/.local/state/selection-dogfood/log status
~/.local/state/selection-dogfood/log record org 2-9 replace ok instant no yes none
```

Run the command without arguments to list every accepted category. It rejects
free-form values, so buffer text and paths cannot accidentally enter the log.
Automated qualification scenarios are stored separately and receive no credit
toward the human episode gate.

## Immediate stop conditions

Stop the dogfood daemon after any data loss, silent or out-of-selection mutation,
unexpected undo boundary, cross-buffer ownership leak, stale session artifact,
repeated client/startup failure, simultaneous Meow/selection-first ownership,
personal content in persistent logs, or blocking latency at ordinary counts.

## Rollback

Close only the dogfood daemon:

```bash
~/.local/state/selection-dogfood/stop
```

Then return to the unchanged production daemon. No Home Manager or NixOS rollback
is required during this isolated phase.

## Promotion gate

Before Home Manager activation, require zero correctness/lifecycle incidents,
30 total, 10 plural, and 5 batch-insert episodes, prompt cancellation/undo/
buffer-kill/restart coverage, no sensitive logging, and a reviewed clean
candidate diff. Build the
lawliet user activation package from the clean candidate branch and inspect its
closure diff before applying it; do not run a full NixOS switch for this phase.
