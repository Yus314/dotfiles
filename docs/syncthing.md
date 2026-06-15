# Syncthing policy

This repository manages personal Syncthing folders declaratively with Nix.

## Active devices

| Device | Role | Policy |
| --- | --- | --- |
| `lawliet` | Primary desktop / source of truth | Syncs all active personal folders. |
| `watari` | Laptop / macOS | Syncs task, review, vault, and knowledge folders needed for mobile work. |
| `android-mole` | Phone / mobile capture | Syncs mobile-facing folders only. |

## Inactive lab devices

`ryuk` and `rem` are currently not used. They should not participate in personal data sync by default.

If either lab host is brought back, personal folders must be re-enabled explicitly and intentionally. Do not add lab hosts to `org-tasks`, `weekly-report`, `obsidian-vault`, `org-knowledge`, or `mole-ledger` just because the device ID exists.

## Folder policy

| Folder ID | Path on Linux | Path on macOS | Devices | Purpose |
| --- | --- | --- | --- | --- |
| `org-tasks` | `/home/kaki/org` | `/Users/kaki/org` | `lawliet`, `watari`, `android-mole` | Active org-mode task system. |
| `weekly-report` | `/home/kaki/weekly-report` | `/Users/kaki/weekly-report` | `lawliet`, `watari`, `android-mole` | Generated and reviewed weekly reports. |
| `obsidian-vault` | `/home/kaki/obsidian-vault` | `/Users/kaki/obsidian-vault` | `lawliet`, `watari`, `android-mole` | User-curated Markdown/Obsidian notes. |
| `org-knowledge` | `/home/kaki/org-knowledge` | `/Users/kaki/org-knowledge` | `lawliet`, `watari` | Org knowledge / org-roam style material. Not mobile-facing by default. |
| `mole-ledger-*` | `/home/kaki/ledger/personal` | n/a | `lawliet`, `android-mole` | MoLe ledger sync bridge. |

## Org workflow

Hermes and related automation should assume the org TODO workflow uses:

```text
TODO WAIT SOMEDAY PROJECT | DONE CANCEL
```

Important files:

- `~/org/inbox/inbox.org`
- `~/org/habit.org`
- `~/org/calendar.org`
- `~/org/kana.org`
- `~/weekly-report/YYYY/MMDD-MMDD.md`

## Safety rules

- Keep folder IDs stable. Changing folder IDs can create duplicate folders or trigger large resyncs.
- Keep device IDs stable. Rename labels only when needed.
- Do not commit runtime Syncthing config files such as `~/.config/syncthing/config.xml`.
- Do not copy Syncthing GUI API keys into this repository.
- Do not edit synced data while refactoring Syncthing config.
- Prefer removing unused devices from folder membership over syncing personal folders to inactive machines.
