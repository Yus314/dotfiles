# watari macOS Kanata production rollout

This directory contains the declarative production configuration for `watari`.
It replaces the Karabiner-Elements/Goku grabber with Kanata while retaining the
pqrs standalone VirtualHID DriverKit dependency.

The input mapping has passed real-device canaries on macOS 26.3/aarch64 with
Kanata 1.12.0. The base migration reported `virtual_hid_keyboard_ready: true`,
grabbed only the intended keyboard, and passed normal interactive use. The Lean
tranches were then confirmed on the physical JIS keyboard: the number-row
`- / =` position emits `\\` and Shift emits `#`; the `¥ / |` position emits `|`
and Shift emits `?`. The declarative focused check and full `watari.system` build
produce the exact config/plist tuple running in the system launchd canary.
A permanent `darwin-rebuild switch` remains a separately approved activation.

## Pinned production tuple

- Kanata: official **1.12.0** macOS arm64 **no-cmd** binary
  (`macos-binaries-arm64.zip`, archive SHA-256
  `839769d189911b5881e11550eaa2039705213fb725865d088f5a2e3a6c10de32`).
- DriverKit package/source: **6.2.0**, fetched from the `v6.2.0` source tag.
- Active system-extension version expected from that package: **1.8.0**.
- Physical input include: exactly **`Apple Internal Keyboard / Trackpad`**.
- Runtime identity: root LaunchDaemon executing
  `/Users/kaki/Applications/KanataCanary.app/Contents/MacOS/kanata_macos_arm64`.
- Stable bundle identity: `local.kaki.kanata-canary`; the tested existing app
  CDHash `8c31a4ec989ae59f4317fe7fa0ad78838f433085` is validated and copied through
  an atomic staging path without re-signing, preserving its code identity.

The generated keymap contains no command action or TCP listener. It retains the
32 Shingeta single-key fallbacks, 102 unordered chords, 40 ms timeout, JIS base
mapping, and synchronized AquaSKK layer transitions validated by the prototype.
Kanata 1.12.0 still has no Karabiner `input_source_if` equivalent, so external
input-source changes can desynchronize AquaSKK and the Kanata layer.

## Declarative lifecycle

`systems/darwin/watari/default.nix` enables the module and disables
`services.karabiner-elements`. `homes/darwin/watari/default.nix` force-disables
Goku only for watari; the shared Darwin desktop default remains unchanged for
other hosts.

Activation installs real copies, not symlinks:

- `/Applications/.Karabiner-VirtualHIDDevice-Manager.app`
- `/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice`
- the stable Kanata app at the path above (only when the tested app cannot be
  safely adopted)

Driver payload replacement uses sibling staging/backup paths and restores the
previous files if either move or post-copy verification fails. This rollback is
for on-disk payloads only: a DriverKit extension transition is macOS state and
may require approval or reboot; never model a live downgrade as an automatic
rollback.

Two root LaunchDaemons are declared. The DriverKit daemon starts at boot and is
kept alive. Kanata's ordering wrapper runs the manager's idempotent `activate`,
kickstarts the daemon, waits up to 30 seconds for its root-only socket, and only
then execs Kanata. Kanata uses `KeepAlive.SuccessfulExit = false`: crashes and
startup failures restart after throttling, while the successful emergency exit
(LCtrl+Space+Escape) intentionally remains stopped.

Logs are separate:

- `/var/log/kanata-virtual-hid-daemon.log`
- `/var/log/kanata-shingeta.log`

## Regenerate and qualify without activation

From a clean checkout containing these files:

```sh
python3 systems/nixos/services/kanata/generate_shingeta.py \
  --platform macos \
  --source systems/nixos/services/xremap/shingeta.yml \
  --output systems/darwin/services/kanata/shingeta.kbd
python3 systems/darwin/services/kanata/test_generate_shingeta.py
nix build '.#checks.aarch64-darwin.shingeta-kanata-macos'
nix build '.#darwinConfigurations.watari.system'
```

When files are not yet tracked, use `path:$PWD#...` so the flake includes them.
On Linux, the focused check replaces only the macOS device selector and provides
common-syntax parser coverage. Exact macOS parsing and the full system build
must run on an aarch64-darwin builder.

The focused check also evaluates production assertions for the exact device,
Kanata/DriverKit versions, root launchd identity, real DriverKit daemon path,
safe successful-exit restart policy, and watari-only Karabiner/Goku disablement.

## Target-host activation and verification

Before switching, preserve SSH/Screen Sharing, the prior nix-darwin generation,
and the current tested app. Confirm both TCC grants still show the exact app in
Input Monitoring and Accessibility. Then build first; inspect the result before
performing a separately approved switch.

After a future switch, verify independently:

```sh
sudo launchctl print system/org.pqrs.Karabiner-VirtualHIDDevice-Daemon
sudo launchctl print system/local.kaki.kanata-shingeta
pgrep -fl 'karabiner_grabber|Karabiner-VirtualHIDDevice-Daemon|kanata_macos_arm64'
tail -n 100 /var/log/kanata-virtual-hid-daemon.log
tail -n 100 /var/log/kanata-shingeta.log
codesign --verify --deep --strict /Users/kaki/Applications/KanataCanary.app
codesign -dvvv /Users/kaki/Applications/KanataCanary.app 2>&1 | grep -E 'Identifier|CDHash'
```

Require `virtual_hid_keyboard_ready` to become true, only the exact internal
keyboard to be grabbed, no `karabiner_grabber`, and no TCC denial. Re-test normal
typing, both chord orders, timeout boundaries, modifier release order, JIS
punctuation, Kana/Eisu/AquaSKK transitions, lock/unlock, sleep/resume, and a
clean stop/start before treating the rollout as persistent.

If the existing tested app is not adopted and activation installs/re-signs a new
bundle, its CDHash can change. Re-add that stable app to both TCC panes and
restart the responsible terminal/session before starting Kanata.

## Rollback

For an immediate stop that remains stopped until the next switch or reboot,
remove the Kanata job from the live launchd domain, then stop the standalone
daemon after Kanata is gone:

```sh
sudo launchctl bootout system/local.kaki.kanata-shingeta
sudo launchctl bootout system/org.pqrs.Karabiner-VirtualHIDDevice-Daemon
```

Verify both processes are absent. The physical keyboard then works without a
remapper. Do not use only `launchctl kill`: a signal exit can satisfy the
failure-only KeepAlive condition and restart Kanata.

Activating the retained previous nix-darwin generation removes the declarative
Kanata jobs and re-enables the old Karabiner/Goku definitions, but it does **not**
make the old remapper usable by itself. The previous Karabiner 14.13 client is a
3.1.0-generation client, while this rollout leaves DriverKit extension 1.8.0
and the 6.2.0 payload active. That exact mismatch was observed during the
canary preparation. Treat a previous-generation switch as a return to an
unmapped keyboard unless the old DriverKit 3.1.0 package is deliberately
reinstalled and macOS is rebooted.

Do not automatically install DriverKit 6.6 or downgrade the active extension.
A full Karabiner rollback is a separate privileged migration: keep competing
grabbers stopped, preserve remote access, verify the signed 3.1.0 rollback
package, reinstall it interactively, reboot, and only then verify that
`karabiner_grabber` reacquires the keyboard. The preferred emergency state is
the safe unmapped keyboard, not an automatic live driver downgrade.
