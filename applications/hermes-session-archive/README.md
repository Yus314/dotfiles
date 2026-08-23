# Hermes cross-node session archive

This module gives `lawliet` and `watari` searchable, source-authoritative copies of
user-facing Hermes sessions without synchronizing either host's live
`state.db`.

## V1 contract

- Each host remains the sole writer of its own `~/.hermes/state.db`.
- The built-in `hermes sessions export --redact` command produces every
  archive version. Raw database rows are never copied into the archive.
  Hermes v0.19 redacts message/segment trees but not top-level free text, so
  the archive additionally applies a strict top-level allowlist. Fields such
  as `system_prompt`, `title`, `model_config`, `cwd`, IDs for external chats,
  and `origin_json` are not synchronized.
- The exporter is append-oriented and namespaces records by node, profile,
  session ID, and a content-state fingerprint. An active session may therefore
  have multiple historical versions without overwrite conflicts. Missing or
  corrupt canonical files are regenerated from the source database.
- The default scheduled scope is the `default` profile and user-facing
  `cli`, `discord`, and `telegram` sources. Subagents, cron runs, and restricted
  profiles are excluded unless explicitly requested.
- Syncthing shares two source-authoritative subfolders only between lawliet and
  watari: each node is `sendonly` for its own folder and `receiveonly` for the
  peer folder. Pixel is not a replica target in V1. Staggered recovery versions
  are retained for one year.
- A node-local SQLite FTS index is rebuilt incrementally from the synchronized
  exports. The index is operational state and is not synchronized.
- Missing exports are regenerated. Invalid exports are preserved with a
  `.jsonl.bad` quarantine suffix before the canonical version is regenerated.
- V1 provides cross-node search, not transparent `/resume`. A later handoff
  command may branch a sealed source session on another node; concurrent
  writers to one logical session remain out of scope.

## Known V1 limits

- Change detection follows Hermes' normal append-only message model plus its
  active/compacted/rewind counters. Unsupported direct in-place edits to a
  message row that preserve those counters are not detected automatically.
- Every immutable revision is retained; automatic archive garbage collection
  is intentionally deferred until real storage growth is measured.
- Search is exposed as `hermes-session-archive search`, not yet merged into the
  native `session_search` tool or `/resume` database.

## Commands

```console
# Export changed sessions and refresh the local index
hermes-session-archive sync

# Search local and synchronized sessions
hermes-session-archive search 'selection first undo'

# Preview candidates without writing
hermes-session-archive export --dry-run

# Accelerate the initial historical backfill
hermes-session-archive sync --max-exports 200
```

Default paths:

- Archive: `~/.local/share/hermes-session-archive`
- Local manifest/index: `~/.local/state/hermes-session-archive`

The scheduled service scans all retained user-facing sessions, exports at most
50 missing or changed versions per run every six hours, uses a lock, writes
through Syncthing's ignored temporary-file convention, and validates every
JSONL record. Invalid files are quarantined rather than destroyed.
Source-authoritative folder modes and regeneration are the consistency
mechanism; Syncthing staggered versioning is additional recovery protection.
The interval reflects a measured full-history fingerprint scan of roughly 24
seconds on lawliet; Honcho remains the lower-latency semantic-memory layer.
