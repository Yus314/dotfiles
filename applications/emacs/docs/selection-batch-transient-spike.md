# Emacs 31 transient-map prompt spike

## Scope and hypotheses

This spike uses stock GNU Emacs 31.0.90 and no production
`selection-batch` functions.  It asks whether:

1. the exit function returned by `set-transient-map` deactivates its map;
2. explicit deactivation invokes `on-exit`, and in what order;
3. a map can be removed before a minibuffer prompt so minibuffer commands do
   not see it;
4. the session can install a fresh transient map after the prompt; and
5. `C-g` can pass through one guarded cleanup/resume path.

The probe is `applications/emacs/tests/selection-batch-transient-spike.el`.
It creates only a sparse transient map; it changes no global keymap.

## Batch observations

Command:

```sh
emacs --batch --quick -L applications/emacs/tests \
  -l selection-batch-transient-spike.el \
  -f ert-run-tests-batch-and-exit
```

Observed result: 2 tests passed, 0 unexpected.

Exact event order for calling the returned exit function was:

```text
active
exit-after-deactivate
inactive-after
```

Thus the returned function removes the map synchronously and invokes
`on-exit` synchronously **after** removal.  Calling it for suspension still
runs `on-exit`; the observed suspend/resume sequence was:

```text
exit-while-suspending
[a fresh map resolves x to selection-batch-spike-supported]
exit-after-deactivate
```

`set-transient-map` may install a composed wrapper rather than making
`overriding-terminal-local-map` `eq` to the supplied sparse map.  Binding
resolution (`key-binding`) is the useful assertion.

## Minibuffer and command-loop limits

Batch Emacs cannot exercise a real minibuffer here: `read-string` reads batch
stdin and signals `end-of-file`, rather than entering an interactive
minibuffer command loop.  The file therefore includes the isolated interactive
command `selection-batch-spike-prompt`.  It deactivates the map first, records
whether the map is absent, invokes `read-string`, and reinstalls a fresh map in
`unwind-protect`.  No interactive GUI/TTY invocation was performed in this
run, so actual keyboard `C-g`, minibuffer key lookup, and an unmatched outer
command remain interactive behavior to verify manually.

Emacs 31's documented `set-transient-map` contract says a map with `KEEP-PRED`
`t` remains when a key from that map is used, while a key not in the map falls
through normal lookup and causes deactivation.  Production tests characterize
the resulting callback policy with injected prompt readers, without pretending
to be a real minibuffer command loop.

## Production contract chosen

- Keep the returned exit function in the session and clear its slot before
  calling it.
- Set `suspending-p` before explicit prompt suspension because explicit exit
  always invokes `on-exit`.
- Let `on-exit` collapse only the same live session, unless it is suspending or
  already exiting.
- After the prompt, validate session identity, owner buffer, current buffer,
  and generation before installing a new transient map.
- On a valid `quit`, restore the transaction map exactly once and re-signal the
  quit.  On stale owner/generation, perform idempotent full cleanup and signal a
  stale-session `user-error` instead of resuming.
- Generic recursive edit is not bound in the transaction map.
