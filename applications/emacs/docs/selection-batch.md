# selection-batch

`selection-batch` is an ordered, single-buffer SelectionSet kernel.  A singleton
uses native point/mark state; two or more selections materialize a session with
markers and derived overlays.  `selection-first` is the Meow-independent modal
frontend over that boundary.  Text mutation still goes through immutable plans;
commands are never replayed once per selection.

## Installation and ownership

Add this repository's `lisp/` directory to `load-path`, require
`selection-first`, and enable either `selection-first-mode` or
`selection-first-global-mode`. The standalone package does not enable itself.

```elisp
(add-to-list 'load-path "/path/to/selection-first.el/lisp")
(require 'selection-first)
(selection-first-global-mode 1)
```

`selection-first` owns its normal grammar independently of Meow. The legacy
`selection-batch-meow.el` adapter remains optional and disabled by default; do
not enable both frontends in the same buffer.

The implemented DVP-oriented normal grammar is intentionally small:

| Phase | Key | Meaning |
|---|---:|---|
| move | `d` / `n` | select previous / next character |
| move | `t` / `s` | move each cursor to the previous / next logical line |
| extend | `D` / `N` | extend cursor backward / forward |
| extend | `T` / `S` | extend cursor to the previous / next logical line |
| move | `b` / `w` | select to previous / next word boundary |
| direction | `;` | reverse anchor and cursor |
| gather | `SPC n` / `SPC p` | add next / previous unselected equal occurrence |
| gather | `SPC a` | gather every occurrence equal to primary |
| refine | `SPC k` / `SPC d` | keep / drop selections matching a regexp |
| operate | `p` / `r` | atomic delete / fixed replace |
| insert | `c` | delete selections and enter interactive insertion |
| insert | `I` / `A` | fixed insertion before / after every selection |
| repeat | `.` | repeat the last semantic recipe on the current selections |
| register | `x` / `y` | vector copy / broadcast-or-pairwise paste |
| history | `SPC u` / `SPC U` | undo / redo selection-only transformations |
| history | `u` | undo one whole-buffer text unit and collapse to singleton |
| insert | `i` / `a` | native singleton insert, or plural batch-insert at beginnings / ends |
| exit | `q` | collapse to primary native region |
| native | `:` | read and execute one native key sequence |
| native | `M-x` | choose and execute one native command by name |
| help | `?` | display the canonical grammar |

Printable keys outside the explicit grammar are rejected by the normal-state map.
Ordinary Emacs commands reached through other bindings remain available. A
single `command-execute` boundary preserves disabled-command handling, keyboard
macros, prefixes, aliases, prompts and error/quit behavior; plural sessions
collapse before a valid native command runs, while singleton history is
invalidated only after a native text change.

Logical-line motion keeps a display-column goal for each selection across a
consecutive `t`/`s`/`T`/`S` run. Short lines clamp at end of line without
inserting whitespace; moving on to a longer line restores the stored goal.
Lowercase motion installs empty carets. If two plural cursors would clamp to the
same target, or uppercase extension would create overlapping linear ranges, the
whole command is rejected without changing the selection set.

Incremental same-text gather keeps the existing set and adds one unselected
literal occurrence with `SPC n` or `SPC p`. The added occurrence becomes primary,
so point follows the review direction; selections remain ordered by buffer
position and existing IDs/directions are preserved. Search does not wrap.
Empty, mixed-text, stale, differently narrowed, exhausted, or non-occurrence
selection sets are rejected before installation. Matching uses Emacs's
non-overlapping literal `search-forward` semantics. `SPC a` remains the explicit
all-occurrences operation.

Selection-only history is available with `SPC u` / `SPC U` after a plural session
has recorded a subsequent transform. The initial singleton-to-plural promotion
has no backend history entry; use `SPC q` to abandon that first gathered set.
Selection undo/redo never changes buffer text and each restoration advances the
snapshot generation. Any successful operator plan clears both selection history
stacks before returning; failed plans restore them. Calling selection history
history from a non-owner buffer errors without collapsing or mutating the real
owner. Plain `u` remains whole-buffer text undo and tears down plural state
before returning to a singleton.

The mode-line shows `Sel N:<count>`, `Sel BI:<count>`, `Sel I`, or `Sel Native`.
`Sel BI:<count>` identifies closed transactional plural insertion ownership;
the count is the number of carets. Both native
handoff routes collapse plural state, invoke one command exactly once, and then
restore normal state in the source buffer only.

## Transactional plural insertion MVP

For a singleton, `i` and `a` retain ordinary native Emacs insertion at the
selection beginning or end. For a plural set they retain the session and replace
each selection with a unique empty caret at the corresponding beginning or end,
then enter `batch-insert`. Same-position carets are rejected rather than merged
or assigned an arbitrary owner.

`c` is the interactive change operator, distinct from prompt-once fixed `r`.
It atomically replaces every selected range with a unique empty caret before
entering native singleton insertion or plural `batch-insert`. Empty selections
remain insertion carets. Overlap or coincident result carets are rejected before
mutation. Thus selecting `in` in `input.file`, then typing `c out Escape`, yields
`output.file`; one `u` restores the original text.

Printable committed input, Return, backward deletion of one character, and
forward deletion of one character are selection-first intents. Each intent is
planned once in original snapshot coordinates and applied once inside its own
rollback boundary; `self-insert-command` is never replayed. Literal Unicode and
multi-character committed strings are supported through the adapter boundary
`selection-first-batch-insert-string`. The insertion planner computes result
carets with one position-ordered cumulative pass instead of the generic
all-edits-against-all-edits result-position loop. Escape or `C-g` leaves
batch-insert for normal state while preserving the plural carets.
Every other command and prefix is rejected at the high-precedence command-loop
boundary before it can mutate only the primary caret. Keys are neither replayed
nor reduced to their final event.

The frontend also retains an ownership fingerprint across intents: owner buffer,
modification tick, session generation, narrowing, and ordered caret IDs and
positions. Validation covers buffer identity, generation, modification tick, narrowing,
read-only targets, boundaries, collisions, and result ownership before text is
committed. During apply, a buffer-local change-hook ledger brackets ordinary
before/after-change hooks by depth and accepts only each primitive's
deterministic delete and insert notifications. Wrong, missing, extra, nested,
widened-outside, and generic hook-driven property changes are rejected;
observation hooks still see the real primitive sequence. An exact adapter may
wrap one named derived-property refresher, but it must hold a capability
registered before plan application, match that capability's exact function
identity, prove that characters, narrowing, modified state, undo ownership,
buffer ownership, and ledger phase are unchanged, and register a recomputation
for later transaction rollback. Ordinary hooks cannot register or nominate a
new trusted refresher while a plan is active.
The only current exception is Org's unadvised `org-indent-refresh-maybe`, which
maintains its derived `line-prefix` and `wrap-prefix` presentation properties.
The adapter captures that exact function identity, fails closed if an inner
advice chain is already present or later changes, and widens only while
recomputing those derived properties after rollback.
Verification uses notifications and modification ticks, not a whole-buffer copy
or comparison. An error or quit rolls back buffer text, undo-recorded
properties, trusted derived properties, and semantic session state, but not
external side effects—or undo-suppressed mutations—performed by arbitrary user
hooks. A compensation failure destroys the session rather than retaining
invalid live markers.

This first MVP intentionally has no abbrev, electric-pair, auto-fill, CAPF,
snippet, or IME preedit integration. Those features require explicit future
adapters that submit committed literal strings; arbitrary command replay remains
out of scope. A continuous `i`, `a`, or `c` typing episode ends at Escape or
`C-g` and is one user-visible undo unit, including `c`'s initial deletion.
Each plural input intent still uses its own immutable plan and atomic rollback
boundary, so a failed intent does not roll back earlier successful intents or
end a valid episode. The frontend holds an inactive prepared change-group
bookmark and uses Emacs's supported undo amalgamation API only at finalization;
no active atomic group spans command-loop iterations and `buffer-undo-list` is
never spliced. While the episode is live, buffer-local undo size limits are
temporarily lifted and restored on every exit. This prevents Emacs's command-loop
garbage collection from truncating the bookmark, at the explicit cost of memory
proportional to the episode's accumulated undo data.

## Legacy guarded Meow adapter

`selection-batch-meow.el` remains available for comparison and rollback. Its
bindings are opt-in through `selection-batch-enable-meow-bindings`, which defaults
to nil. No selection-first command reads Meow state or calls a Meow command
implementation.

### Explicit kill-ring bridge

The typed vector register never enters the scalar kill ring implicitly.  Call
`selection-batch-register-to-kill-ring` explicitly and supply the exact
separator used to join vector elements (the interactive default is a newline).
Selection boundaries cannot be reconstructed from that scalar.  This bridge has
no direct key in either the `g` grammar or the active transaction map; invoke it
by command name or add an intentional user binding.

## Handoff contract

`selection-batch-export-ranges` returns logical-order integer plists containing
`:buffer`, `:id`, `:anchor`, `:cursor`, `:beginning`, `:end`, `:forward`, and
`:primary`. It exports no markers or overlays.

`selection-batch-collapse-and-call` destroys secondary markers, overlays, hooks,
and the transient map, preserves the primary point/mark region, and only then
calls one interactive command once. A backend error therefore leaves ordinary
point/mark ownership rather than a half-live batch session.

Intended routes:

- fixed transform → a typed batch operator
- same-occurrence live editing → explicit iedit handoff after collapse
- a few arbitrary carets → explicit, constrained multiple-cursors handoff
- complex sequence → collapse, then kmacro/Beacon
- semantic rename → collapse, then call Eglot once
- project edit → Consult/Embark review buffer, never a multi-buffer session

## Deliberate limitations

There is no arbitrary command replay, automatic multiple-cursors automation,
per-selection LSP request fanout, or project/multi-buffer selection set. Special
modes, minibuffers, and read-only buffers reject activation. Transactions are
single editable text buffers and fixed operators use immutable plans.

## Manual dogfood checklist

Before enabling the global mode for daily work, manually exercise plain text at
10/100 targets,
Japanese fixed replace, Org and Python/Nix tree-sitter buffers, Eglot connected
and disconnected, prompt `C-g`, undo/redo/vundo, buffer switch/kill, narrowing,
multiple windows, and rejection in Dired/Magit/Org agenda. Record only intent,
selection-count class, result, latency class, fallback, and missing adapter; do
not retain buffer contents.

## Tests

Run the source gates with:

```bash
applications/emacs/tests/run-selection-batch-tests.sh
applications/emacs/tests/run-selection-batch-tests.sh --benchmark
nix build --no-link path:.#checks.x86_64-linux.selection-batch-configured-smoke
nix build --no-link path:.#checks.x86_64-linux.selection-batch-minimal-configured-smoke
nix build --no-link path:.#checks.x86_64-linux.selection-batch-minimal-package-smoke
nix flake check path:.
```

ERT, warning-as-error byte compilation, a minimal load smoke, package building,
and the opt-in benchmark are independent gates. They use synthetic buffers and
do not read the user's Emacs configuration.

## Opt-in benchmark

The ordinary runner remains the quick ERT allowlist. Run the performance fixture
explicitly; it does not tangle files or read user configuration:

```bash
applications/emacs/tests/run-selection-batch-tests.sh --benchmark
```

The benchmark loads the actual package before timing, then uses fresh synthetic
`fundamental-mode` ASCII buffers with 10, 100, and 1000 disjoint selections. For
each count it measures five paths separately: pure selection-first character
transform, snapshot/session installation (including its initial view), explicit
overlay refresh, fixed insertion plan construction plus atomic apply, and the
plural batch-insert committed-text intent. Each median is
from five timed iterations after two untimed warmups. Process startup, package
loading, fixture construction, and teardown are outside samples.

Every iteration checks exact final text (plus SHA-256 for insertion), selection
count, generation where applicable, and overlay cardinality. Cleanup checks the
captured marker and overlay objects are detached, no tagged buffer overlay or
lifecycle hook remains, and the global session is nil. Thus the 1000-selection
rows are also deterministic completion/leak tests, not just timings.

Output contains human-readable `BENCH` lines and one machine-readable
`SELECTION_BATCH_BENCHMARK_JSON` line with raw elapsed samples, median, GC counts,
and GC seconds. The command exits nonzero unless the provisional engineering
gates hold: the 1000-selection pure transform median is below 20 ms; at 100
selections, insertion plan+apply is below 200 ms and overlay refresh below 100
ms; the 1000-caret batch-intent median is below 500 ms; and the 10-caret,
200,000-character large-buffer fixture stays below 50 ms and five times the
small-buffer 10-caret median. The separate large-buffer fixture exposes
accidental whole-buffer verification without conflating buffer size with caret
count. These are regression gates and diagnostic measurements, not latency
promises across machines.

Baseline methodology recorded on Emacs 31.0.90, x86_64 Linux: three independent
batch processes, each with two warmups and five samples per row. The observed
100-selection medians were 76.3--77.3 ms for insertion plan+apply and 1.69--1.91 ms for
overlay refresh; all three 1000-selection runs completed and passed cleanup.
Raw per-process summaries should be retained in the validation report because
host load and garbage collection affect individual samples.
