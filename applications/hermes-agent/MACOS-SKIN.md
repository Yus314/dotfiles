# Watari CLI appearance following

Watari's packaged Hermes follows macOS appearance for local, interactive
`default`-profile chat launches. Both the classic CLI (`hermes`) and the
NEW TUI (`hermes --tui`) follow changes while running.
The existing `display.interface` selection is not changed by this feature.
No independent background service is installed.

- Dark: `modus-vivendi`; light: `modus-operandi`.
- The saved `display.skin` is not rewritten. `default` and the two Modus
  names opt into automatic selection; an explicit different skin (for
  example `slate`) takes precedence.
- In either authorized renderer, manual `/skin NAME` fixes the selection for the
  session; `/skin auto` resumes macOS following. Neither writes the saved
  skin. Outside that scope, manual selection retains upstream behavior.
- `HERMES_MACOS_SKIN_SYNC=0 hermes` disables following for that launch.
- Named profiles (including `math`), SSH, redirected input/output, `-q`, and
  `--ignore-user-config` are excluded. Gateway/cron/ACP commands do not arm
  the policy. No credentials or config files are read by the policy itself.
- Standard CLI and the Node TUI share the skin-engine initialization hook.
  The TUI child rechecks the resolved profile home before applying a skin.
- The NEW TUI periodically requests a refresh from its own backend. Failed
  appearance probes retain the last good palette. The classic CLI checks
  every three seconds using a task owned by its prompt_toolkit application.
  Appearance detection runs off the UI thread; only actual palette changes
  refresh the prompt, rules, completion menu and status bar. Typed text and
  its background retain terminal-default colors, matching Ghostty's theme.
  Input buffers, cursor and selection are preserved. An in-flight probe
  cannot override a newer manual choice, and polling ends when the UI exits.
  The cached light-mode remap is updated without reading terminal input.

Watari opts into `hermesMacosLiveSkin`. The Nix build applies the backend
and frontend patches and rebuilds the actual bundled renderer. Both the
skin colors and the base light/dark palette must change together.

The package wrapper supplies `HERMES_MACOS_SKIN_HOME` for the default home.
`prepare_chat` arms a process-local marker only after Hermes resolves the
profile. `select_skin` applies the policy in the common skin engine. Linux
continues using the unchanged source plane and existing darkman policy.

## Verification

Run the isolated policy tests with Python 3.12 or newer:

```sh
python3 -m unittest discover -s applications/hermes-agent/tests -p test_macos_skin.py -v
make build
```

The Darwin source derivation also runs the startup/live policy, classic CLI and backend
integration tests and applies the backend patches with zero fuzz. The
Gateway package and Linux source plane do not receive these patches.
Isolated tests do not change system appearance, profiles, or credentials.

Classic regression tests exercise dark/light/dark changes with real
prompt_toolkit styles, manual/auto races, unchanged input state, and real
application shutdown cancellation. Run them against the patched source with
`PYTHONPATH=/path/to/patched/hermes python -m unittest discover -s applications/hermes-agent/tests -p 'test_macos_skin*.py'`.

Runtime acceptance is separate from unit tests: check both rendered Modus
palettes, normal CLI and TUI startup, `/skin`, the named-profile exclusion,
and unchanged saved config before manual selection. A mocked light-mode probe does
not prove a live macOS light-mode transition. Ghostty uses the same
light/dark Modus pair; terminal-specific appearance overrides may differ
from macOS and are not synchronized by this policy.

## Rollback

Deployment is a separate approval gate. Before system activation, record
config hashes and the Gateway PID/launch definition. Full Home Manager
activation may regenerate the managed math config via existing hooks even
though the skin policy itself never writes config; do not claim byte-level
preservation without comparing the post-activation files. Keep the built
system GC-rooted and account for Nix auto-GC during the activation command.

`HERMES_MACOS_SKIN_SYNC=0` is the immediate per-launch escape hatch. Reverting
the Darwin source-plane/wrapper changes disables the policy for subsequent
launches; no mutable skin config needs restoring. Existing sessions and
Gateway processes are never restarted by the skin policy.
