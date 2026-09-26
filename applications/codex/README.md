# Codex mutable configuration

Home Manager generates declarative Codex settings in the Nix store, but Codex
writes project trust and TUI state into the same user config. A store symlink
causes `config/batchWrite` to fail with JSON-RPC error -32603.

This module retains `programs.codex.settings` and Home Manager's generated source
(including MCP integration), disables only its config.toml symlink, and overlays
that source onto a writable user file during activation.

- Explicitly declared leaves win on activation; other runtime keys and comments
  survive. Arrays are replaced, not concatenated.
- Run after `writeBoundary`, before `linkGeneration`: otherwise cleanup can
  remove the old config link before its contents are migrated.
- Existing contents are backed up beside the config as `config.toml.backup-*`.
  Backups and the materialized file have mode 0600. Backups may contain private
  settings; do not commit them.
- Invalid TOML and broken links fail without overwriting the original.
- Replacement is atomic. Do not change settings in Codex during activation:
  Codex and Home Manager have no shared writer lock. The script detects changes
  before replacement but cannot eliminate the final check/rename race.
- Removing a key from Nix relinquishes its management; it does not delete the
  existing user value. Remove that value manually if it is no longer wanted.
- Old generations still contain the immutable-file definition. Rolling back to
  one can cause a Home Manager file collision; the mutable file/backups must be
  preserved when resolving it, rather than overwritten.
- Trust is not granted by this migration. Make trust decisions in Codex as usual.

The helper's unit tests run in its derivation, so `make build` also exercises them.
For focused tests, use Python with `tomlkit`:

    python -m unittest discover -s applications/codex -p 'test_*.py' -v

References:

- https://developers.openai.com/codex/config-basic/
- https://github.com/nix-community/home-manager/issues/9397
- Pinned implementation: home-manager revision
  `7566825d4652a1b885bd4ce65bd9e8def432fec9`,
  `modules/programs/codex/default.nix` and `modules/files.nix`.
