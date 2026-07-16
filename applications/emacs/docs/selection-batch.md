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
