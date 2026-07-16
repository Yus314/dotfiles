# selection-batch

`selection-batch` is a short-lived, ordered, single-buffer selection transaction.
Normal Meow point/mark selection remains the default. A provider result with one
target stays a standard region; only two or more targets create a session and
its transient map.

## Guarded Meow frontend

The frontend is disabled by default:

```elisp
(setq selection-batch-enable-meow-bindings t) ; user configuration, opt in
```

The active `init-editing` map was inventoried before choosing the prefix.
Lowercase `g` was unbound (the old Avy line is commented); uppercase `G` remains
`meow-grab`. Initialization refuses to overwrite `g` if another configuration
has claimed it.

Both `g KEY` in Meow normal state and `KEY` during a promoted transaction use
the same grammar:

| Phase | Key | Command |
|---|---:|---|
| gather | `n` / `p` / `a` | same text next / previous / all |
| gather | `r` | regexp in accessible text |
| gather | `l` | split selections into lines |
| refine | `k` / `d` | keep / drop by regexp |
| refine | `m` | merge overlaps |
| refine | `]` / `[` | rotate primary next / previous |
| refine | `u` / `U` | selection-only undo / redo |
| operate | `y` | copy to typed vector register |
| operate | `x` / `c` | delete / fixed replace |
| operate | `+` / `-` / `~` | uppercase / lowercase / capitalize |
| operate | `b` / `i` | fixed insert before / after |
| operate | `P` | broadcast or pairwise typed paste |
| operate | `.` | semantic repeat (replans; no command replay) |
| exit | `q` / `C-g` | collapse to primary / cancel |

A key outside the transient grammar collapses to the primary standard region
before Emacs dispatches that key once. Package loading does not enable a global
or session mode and does not start a session.

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

## Guarded rollout checklist

Before enabling the user option, manually exercise plain text at 10/100 targets,
Japanese fixed replace, Org and Python/Nix tree-sitter buffers, Eglot connected
and disconnected, prompt `C-g`, undo/redo/vundo, buffer switch/kill, narrowing,
multiple windows, and rejection in Dired/Magit/Org agenda. Record only intent,
selection-count class, result, latency class, fallback, and missing adapter; do
not retain buffer contents.

## Tests

Run the fast source tests and the disposable Home Manager configured smoke with:

```bash
applications/emacs/tests/run-selection-batch-tests.sh
nix build .#checks.x86_64-linux.selection-batch-configured-smoke
```

The Nix check evaluates `applications/emacs/default.nix`, replaces its heavyweight
Emacs and unrelated home packages only inside a disposable configuration, and
runs ERT against the resulting XDG Emacs files.

## Opt-in benchmark

The ordinary runner remains the quick ERT allowlist. Run the performance fixture
explicitly; it does not tangle files or read user configuration:

```bash
applications/emacs/tests/run-selection-batch-tests.sh --benchmark
```

The benchmark loads the actual package before timing, then uses fresh synthetic
`fundamental-mode` ASCII buffers with 10, 100, and 1000 disjoint selections. For
each count it measures three paths separately: snapshot/session installation
(including its initial view), an explicit overlay refresh of an installed
session, and fixed insertion plan construction plus atomic apply. Each median is
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
gates hold: at 100 selections, insertion plan+apply median is below 200 ms and
overlay refresh median is below 100 ms. These are regression gates, not latency
promises across machines.

Baseline methodology recorded on Emacs 31.0.90, x86_64 Linux: three independent
batch processes, each with two warmups and five samples per row. The observed
100-selection medians were 76.3--77.3 ms for insertion plan+apply and 1.69--1.91 ms for
overlay refresh; all three 1000-selection runs completed and passed cleanup.
Raw per-process summaries should be retained in the validation report because
host load and garbage collection affect individual samples.
