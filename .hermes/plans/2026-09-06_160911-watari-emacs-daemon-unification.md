# Emacs Daemon Cross-Platform Unification Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Unify Linux and watari around one Home Manager-managed Emacs daemon and one `emacsclient` frame-entry path, while preserving macOS app-bundle behavior, Nix package visibility, and unsaved-buffer safety across Home Manager generations.

**Architecture:** `programs.emacs.finalPackage` remains the single package authority. Linux continues to use the Home Manager systemd user service; Darwin uses the Home Manager launchd agent but overrides its command to a stable per-user shim, preventing Home Manager activation from restarting an Emacs process with unsaved buffers when the Nix store path changes. A shared `emacs-frame` command starts the managed service if needed and invokes the matching `emacsclient`; watari additionally gets a native `Emacs Client.app` with a unique bundle identifier.

**Tech Stack:** Nix Flakes, Home Manager, systemd user services, macOS launchd, Emacs Lisp/ERT, `emacsWithPackagesFromUsePackage`, `makeBinaryWrapper`, Home Manager `copyApps`, Nix flake checks.

---

## 1. Current context and confirmed facts

- Shared Home Manager configuration imports:
  - `applications/emacs-minimal/default.nix`
  - `applications/emacs-minimal/service.nix`
- `applications/emacs-minimal/service.nix:4` currently enables `services.emacs` only on Linux.
- The service package is already correctly fixed to `config.programs.emacs.finalPackage`.
- Linux uses `${finalPackage}/bin/emacs --fg-daemon` under a systemd user unit.
- Niri already invokes `emacsclient -c -a ""` from `applications/niri/default.nix:90-95`.
- watari currently runs a normal GUI Emacs, not a daemon. Its server exists only because `server-start` was invoked manually.
- Home Manager `copyApps` is active because `home.stateVersion = "26.05"`; its stable published app directory is `~/Applications/Home Manager Apps`.
- The copied `Emacs.app` wrapper can locate both `exec-path-from-shell` and `lean4-mode`.
- Home Manager commit `7566825d4652a1b885bd4ce65bd9e8def432fec9` defines the Darwin service as `${cfg.package}/bin/emacs --fg-daemon`.
- The same Home Manager launchd module unloads and bootstraps an agent whenever its plist changes. A direct Nix store path in `ProgramArguments` therefore risks terminating a daemon containing unsaved buffers on a package update.
- Linux avoids that behavior with `X-RestartIfChanged=false`; Darwin has no corresponding launchd field.
- `applications/emacs-minimal/elisp/modules/init-core.org:8` currently gates `exec-path-from-shell` on `window-system`. During daemon initialization `window-system` is `nil`, so the current code skips the environment import.
- Existing GUI Emacs PID 17440 has an unsaved Lean buffer. No activation or process termination may occur before a separate user approval gate and buffer-safety check.

## 2. Acceptance criteria

### Declarative configuration

1. `services.emacs.enable` evaluates to `true` on Linux and Darwin.
2. `services.emacs.package` equals `programs.emacs.finalPackage` on every host.
3. Linux retains systemd management and does not restart the daemon merely because a Home Manager generation changes.
4. Darwin launchd `ProgramArguments` contains only a stable home path plus `--fg-daemon`; it must not contain a generation-specific `/nix/store/...emacs...` path.
5. The stable Darwin shim executes the `.app` wrapper from the current `programs.emacs.finalPackage`.
6. Both platforms expose `emacs-frame`, and it starts the managed service rather than falling back to an unmanaged daemon.
7. Niri uses `emacs-frame` instead of raw `emacsclient -a ""`.
8. Darwin exposes `Emacs Client.app` with a unique bundle ID and a native Mach-O executable.

### Runtime behavior

1. `(daemonp)` returns non-nil on watari and Linux when the service is active.
2. `emacsclient` reports the expected server and package generation.
3. `exec-path-from-shell`, `lsp-mode`, and `lean4-mode` are visible in the daemon.
4. Opening a `.lean` file through `emacs-frame` produces `lean4-mode` and an initialized Lean LSP workspace.
5. Creating multiple frames does not create a second Emacs daemon.
6. A Home Manager switch with an unchanged launchd plist does not terminate the running watari daemon.
7. A package-generation change updates the stable shim but leaves the running daemon untouched; the next intentional daemon start uses the new generation.
8. Clean daemon exit is not immediately restarted by `KeepAlive`; invoking `emacs-frame` starts it again.

### Safety

1. Activation never kills a running Emacs daemon solely to deploy a new generation.
2. No restart command proceeds while modified buffers exist.
3. Rollback to direct `~/Applications/Home Manager Apps/Emacs.app` launch remains available until daemon canary verification is complete.
4. Broad LaunchServices database resets are not used.

## 3. Proposed file layout

Likely modifications:

- `applications/emacs-minimal/service.nix`
  - Enable daemon cross-platform.
  - Define stable Darwin daemon shim.
  - Define shared `emacs-frame` and safe status/restart commands.
  - Override Darwin launchd `ProgramArguments`.
  - Install Darwin client app.
- `applications/emacs-minimal/client-app.nix`
  - New derivation for a native `Emacs Client.app`.
- `applications/emacs-minimal/elisp/modules/init-core.org`
  - Make shell-environment initialization daemon-aware.
- `applications/emacs-minimal/emacspkg/emacs-config.org`
  - Regenerated package-discovery source after Org changes.
- `applications/niri/default.nix`
  - Replace raw `emacsclient` invocation with `emacs-frame`.
- `applications/emacs/tests/emacs-daemon-configured-smoke.nix`
  - New cross-platform module-evaluation/build test.
- `applications/emacs/tests/emacs-daemon-init-test.el`
  - New daemon-initialization ERT test.
- `applications/emacs/tests/selection-batch-minimal-package-smoke.nix`
  - Add Darwin `.app` wrapper package-visibility test.
- `flake.nix`
  - Register the new smoke test as a package/check.

Possible modification only if the daemon frame canary demonstrates a real defect:

- `applications/emacs-minimal/elisp/modules/init-ui.org`
  - Move only proven frame-dependent setup into an idempotent frame hook.

Do not edit the full legacy `applications/emacs/` profile unless tests prove it is still imported by an active host. The current shared profile is `applications/emacs-minimal/`.

---

## Task 1: Establish a clean baseline and protect the live GUI session

**Objective:** Record the pre-change configuration and explicitly separate build-only work from live activation.

**Files:** None.

**Step 1: Recheck repository state**

Run:

```bash
git status --short --branch
git diff --stat
```

Expected:

- Existing user changes, if any, are identified before edits.
- No file is overwritten or reverted.

**Step 2: Record current service evaluations**

Run:

```bash
nix eval --json .#nixosConfigurations.lawliet.config.home-manager.users.kaki.services.emacs.enable
nix eval --json .#darwinConfigurations.watari.config.home-manager.users.kaki.services.emacs.enable
nix eval --raw .#darwinConfigurations.watari.config.home-manager.users.kaki.programs.emacs.finalPackage.outPath
```

Expected baseline:

- lawliet: `true`
- watari: `false`
- watari final package: a package-qualified Emacs store path

**Step 3: Record live watari state without changing it**

Run:

```bash
emacsclient --eval '(list :daemonp (daemonp) :pid (emacs-pid) :modified (mapcar #'buffer-name (seq-filter (lambda (b) (with-current-buffer b (buffer-modified-p))) (buffer-list))))'
```

Expected:

- `:daemonp nil`
- Modified buffers are listed, including the current Lean work if still unsaved.

**Step 4: Declare the activation boundary**

Do not run `nh darwin switch`, `home-manager switch`, `launchctl bootout`, `kill-emacs`, or quit the GUI process during Tasks 1–10. Those are reserved for the explicit canary approval gate in Task 11.

---

## Task 2: Add failing service-architecture evaluation tests

**Objective:** Specify the unified service topology before changing the service module.

**Files:**

- Create: `applications/emacs/tests/emacs-daemon-configured-smoke.nix`
- Modify: `flake.nix:135-166`

**Step 1: Create a Home Manager evaluation fixture**

Build a test Home Manager configuration using:

- `applications/emacs-minimal/default.nix`
- `applications/emacs-minimal/service.nix`
- A temporary username/home directory
- The current per-system `pkgs`

The test must assert:

```nix
home.config.services.emacs.enable
home.config.services.emacs.package.outPath
  == home.config.programs.emacs.finalPackage.outPath
```

On Linux, assert:

```nix
home.config.systemd.user.services.emacs.Unit.X-RestartIfChanged == false
```

On Darwin, assert all of the following:

```nix
home.config.launchd.agents.emacs.domain == "gui"
home.config.launchd.agents.emacs.config.ProgramArguments == [
  "/tmp/emacs-daemon-smoke/.local/bin/emacs-daemon"
  "--fg-daemon"
]
```

Also assert that the stable home-file executable and shared client command exist in evaluated configuration.

**Step 2: Register the test in `flake.nix`**

Add `emacs-daemon-configured-smoke` beside the existing Emacs smoke packages and checks. Keep it available for all systems; use conditional assertions internally for Linux versus Darwin.

**Step 3: Run the test and observe the expected failure**

Run on watari:

```bash
nix build --no-link --show-trace .#checks.aarch64-darwin.emacs-daemon-configured-smoke
```

Expected: FAIL because watari currently has `services.emacs.enable = false`, has no stable shim, and has no client app.

Run the Linux evaluation/build if a builder is available:

```bash
nix build --no-link --show-trace --system x86_64-linux .#checks.x86_64-linux.emacs-daemon-configured-smoke
```

Expected: FAIL only on newly specified shared-client requirements; existing Linux package and restart-safety assertions should already pass.

---

## Task 3: Make Emacs environment initialization daemon-aware

**Objective:** Ensure package tools and shell-derived variables are initialized when Emacs starts before any GUI frame exists.

**Files:**

- Modify: `applications/emacs-minimal/elisp/modules/init-core.org:6-13`
- Create: `applications/emacs/tests/emacs-daemon-init-test.el`
- Regenerate: `applications/emacs-minimal/emacspkg/emacs-config.org`

**Step 1: Write a failing ERT test**

The test should temporarily make `window-system` nil, stub `daemonp` to return non-nil, and stub `exec-path-from-shell-initialize` to record invocation. It must verify:

- Daemon startup invokes the shell-environment initializer.
- A terminal non-daemon batch process does not invoke it unintentionally.
- `GNUPGHOME`, `NIX_PATH`, and `ELAN_HOME` are included exactly once in `exec-path-from-shell-variables`.

**Step 2: Run the test and verify failure**

Run it through the package-qualified Emacs used by the minimal smoke test.

Expected: FAIL because the current condition checks only `window-system`.

**Step 3: Extract an idempotent initializer**

Replace the inline block with one named function, conceptually:

```elisp
(defun my/initialize-shell-environment ()
  "Import the login-shell environment once for GUI or daemon Emacs."
  (unless my/shell-environment-initialized-p
    (require 'exec-path-from-shell)
    (dolist (variable '("GNUPGHOME" "NIX_PATH" "ELAN_HOME"))
      (add-to-list 'exec-path-from-shell-variables variable))
    (exec-path-from-shell-initialize)
    (setq my/shell-environment-initialized-p t)))

(when (or (daemonp) (memq window-system '(mac ns x pgtk)))
  (my/initialize-shell-environment))
```

Use a `defvar` for the guard and preserve project formatting. Include `pgtk` because Linux uses PGTK Emacs.

**Step 4: Regenerate the package-discovery input**

Run:

```bash
python3 applications/emacs/generate-package-config.py --profile minimal
```

Expected: only `applications/emacs-minimal/emacspkg/emacs-config.org` changes to mirror the source Org modules.

**Step 5: Run the ERT and existing minimal configured smoke tests**

Run:

```bash
nix build --no-link --show-trace .#checks.aarch64-darwin.selection-batch-minimal-configured-smoke
```

Also run the new daemon-init test through its registered check.

Expected: PASS.

---

## Task 4: Add a stable Darwin daemon shim

**Objective:** Keep the launchd plist stable across Nix generations while ensuring every new daemon uses the current package-qualified `.app` wrapper.

**Files:**

- Modify: `applications/emacs-minimal/service.nix`
- Test: `applications/emacs/tests/emacs-daemon-configured-smoke.nix`

**Step 1: Extend the failing test**

Require a home-file at:

```text
~/.local/bin/emacs-daemon
```

Its generated target must execute:

```text
${config.programs.emacs.finalPackage}/Applications/Emacs.app/Contents/MacOS/Emacs
```

and forward all arguments unchanged.

**Step 2: Define the Darwin shim**

In `service.nix`, define a `pkgs.writeShellScript` or equivalent derivation that contains only:

```bash
exec "${config.programs.emacs.finalPackage}/Applications/Emacs.app/Contents/MacOS/Emacs" "$@"
```

Publish it through:

```nix
home.file.".local/bin/emacs-daemon".source = ...;
```

The home path is stable; only the symlink target changes with the generation.

**Step 3: Enable the service on supported hosts**

Change the service policy from Linux-only to Linux-or-Darwin, preferably using modern platform fields:

```nix
enable = pkgs.stdenv.hostPlatform.isLinux || pkgs.stdenv.hostPlatform.isDarwin;
```

Retain:

```nix
package = config.programs.emacs.finalPackage;
defaultEditor = false;
startWithUserSession = "graphical";
```

**Step 4: Override only Darwin `ProgramArguments`**

Use `lib.mkIf` plus `lib.mkForce` so Darwin evaluates to exactly:

```nix
[
  "${config.home.homeDirectory}/.local/bin/emacs-daemon"
  "--fg-daemon"
]
```

Do not embed `finalPackage` in the launchd plist.

**Step 5: Verify activation-safety statically**

Build the Home Manager activation package twice, once with the current Emacs package and once with a harmless overridden package identity. Compare rendered Emacs plists.

Expected:

- Plists are byte-identical if only the daemon shim target changes.
- Shim targets differ.
- Therefore Home Manager launchd activation takes its “already up-to-date” path and does not call `bootoutAgent`.

**Step 6: Run configured smoke tests**

Expected: Darwin service assertions now pass. No live launchd service has been activated yet.

---

## Task 5: Add a managed, cross-platform `emacs-frame` command

**Objective:** Ensure every frame request uses the Home Manager-managed daemon and matching `emacsclient`, without `-a ""` creating an unmanaged daemon.

**Files:**

- Modify: `applications/emacs-minimal/service.nix`
- Test: `applications/emacs/tests/emacs-daemon-configured-smoke.nix`

**Step 1: Specify client behavior in tests**

The generated command must:

1. Probe the exact `${finalPackage}/bin/emacsclient`.
2. If the server is absent:
   - Linux: run `systemctl --user start emacs.service`.
   - Darwin: run `launchctl kickstart gui/$UID/org.nix-community.home.emacs`.
3. Retry connection with a bounded timeout.
4. Execute `${finalPackage}/bin/emacsclient --create-frame` with forwarded file arguments.
5. Exit nonzero with a clear diagnostic if the managed daemon does not become ready.
6. Never use an empty alternate editor to spawn an unmanaged daemon.

**Step 2: Implement `emacs-frame` as `pkgs.writeShellApplication`**

Use platform-specific command fragments selected at Nix evaluation time. Use exact store paths for `emacsclient`; use system absolute paths for `/bin/launchctl` and `/usr/bin/id` on Darwin. Keep the retry bounded, for example 50 attempts at 100 ms.

The probe should use a side-effect-free expression such as:

```text
(list :daemonp (daemonp) :pid (emacs-pid))
```

Reject a reachable non-daemon server so the command does not silently attach to an accidentally started GUI Emacs.

**Step 3: Install the command in `home.packages`**

The executable name must be exactly `emacs-frame` on both platforms.

**Step 4: Test with fake service-manager and client binaries**

Provide a test harness that shadows or parameterizes the service-manager calls, verifies retry behavior, verifies argument forwarding, and verifies that failure does not invoke any alternate editor.

**Step 5: Run shellcheck through the repository pre-commit configuration**

Expected: PASS.

---

## Task 6: Route Niri through the managed client

**Objective:** Make Linux use the same managed frame-entry abstraction as Darwin.

**Files:**

- Modify: `applications/niri/default.nix:90-95`

**Step 1: Add/evaluate a failing assertion**

Assert that the `Mod+E` action resolves to `emacs-frame`, not raw `emacsclient`.

**Step 2: Replace the existing action**

Change:

```nix
[
  "emacsclient"
  "-c"
  "-a"
  ""
]
```

into the project-style equivalent of:

```nix
"emacs-frame"
```

**Step 3: Evaluate lawliet and build the Linux check**

Expected:

- Niri configuration evaluates.
- `emacs-frame` is present in the Home Manager user environment.
- No unmanaged fallback remains in the Niri binding.

---

## Task 7: Build a native Darwin `Emacs Client.app`

**Objective:** Provide a Dock/Spotlight entry with an identity separate from `org.gnu.Emacs` that invokes `emacs-frame`.

**Files:**

- Create: `applications/emacs-minimal/client-app.nix`
- Modify: `applications/emacs-minimal/service.nix`
- Test: `applications/emacs/tests/emacs-daemon-configured-smoke.nix`

**Step 1: Write the failing bundle test**

Require:

```text
Applications/Emacs Client.app/Contents/Info.plist
Applications/Emacs Client.app/Contents/MacOS/EmacsClient
```

Validate:

- `CFBundleIdentifier = dev.yus314.emacs-client`
- `CFBundleExecutable = EmacsClient`
- `CFBundleName = Emacs Client`
- `CFBundlePackageType = APPL`
- executable is Mach-O arm64 on watari, not a shell script
- executing it invokes `emacs-frame`

Do not claim file-opening support through Finder until Apple Event handling has been explicitly tested. Initial scope is Dock/Spotlight frame creation.

**Step 2: Implement the app derivation**

Use `makeBinaryWrapper` to produce a native wrapper around `${emacsFrame}/bin/emacs-frame`, rather than placing a shell script directly at `CFBundleExecutable`.

Create a minimal `Info.plist` with the unique bundle ID. Reuse the Emacs icon from `${finalPackage}/Applications/Emacs.app/Contents/Resources/Emacs.icns` if available, and declare `CFBundleIconFile` only when the copied resource exists.

**Step 3: Add the app to `home.packages` on Darwin only**

Home Manager `copyApps` should publish it at:

```text
~/Applications/Home Manager Apps/Emacs Client.app
```

Do not modify the original package-qualified `Emacs.app` or its `org.gnu.Emacs` bundle identity.

**Step 4: Build and inspect without launching**

Run:

```bash
nix build --no-link --show-trace .#checks.aarch64-darwin.emacs-daemon-configured-smoke
```

Inspect the built app with `file`, `plutil`, and `codesign --verify` as applicable.

Expected: native executable, valid plist, unique identifier, no secrets or mutable store references outside intended Nix closures.

---

## Task 8: Add Darwin `.app` package-visibility regression coverage

**Objective:** Catch any future state where CLI Emacs sees Nix packages but GUI app Emacs does not.

**Files:**

- Modify: `applications/emacs/tests/selection-batch-minimal-package-smoke.nix:46-82`

**Step 1: Add a Darwin-only test command**

Use:

```text
${home.config.programs.emacs.finalPackage}/Applications/Emacs.app/Contents/MacOS/Emacs
```

with `--batch --quick`.

**Step 2: Assert package visibility**

Fail unless all are non-nil:

- `(locate-library "exec-path-from-shell")`
- `(locate-library "lsp-mode")`
- `(locate-library "lean4-mode")`
- `(getenv "emacsWithPackages_siteLisp")`

Also open a temporary `.lean` file, run `normal-mode`, and assert `major-mode` is `lean4-mode`. Do not start a real LSP process inside the Nix sandbox.

**Step 3: Preserve a dedicated log artifact**

Copy the result to `$out/darwin-app-smoke.log` beside existing logs.

**Step 4: Run the Darwin package smoke check**

Expected: PASS with the current wrapped app.

---

## Task 9: Add safe daemon status and restart tooling

**Objective:** Make generation drift visible and allow intentional restart without discarding modified buffers.

**Files:**

- Modify: `applications/emacs-minimal/service.nix`
- Test: `applications/emacs/tests/emacs-daemon-configured-smoke.nix`

**Step 1: Add `emacs-daemon-status`**

The command must report:

- whether the managed service is loaded/active
- whether the Emacs server is reachable
- `(daemonp)`
- PID
- `emacs-version`
- package/site-lisp path
- availability of `exec-path-from-shell`, `lsp-mode`, and `lean4-mode`
- whether the running daemon package differs from the current `finalPackage`

Keep output textual and suitable for terminal diagnosis.

**Step 2: Add `emacs-daemon-restart` with a hard safety gate**

Before stopping anything, query all buffers. Refuse restart if any user-relevant modified buffer exists and print its name. At minimum, treat every modified file-visiting buffer as blocking. Do not provide a `--force` bypass in the first implementation.

If safe:

1. Request a clean daemon exit.
2. Wait for the old PID/socket to disappear.
3. Start the managed systemd/launchd service.
4. Wait for `(daemonp)` to become non-nil.
5. Print old and new package generations.

**Step 3: Test refusal and success paths using a fake client**

Expected:

- Modified buffers: nonzero exit, no stop command issued.
- No modified buffers: managed stop/start sequence issued.
- Restart timeout: nonzero exit with actionable diagnostic.

---

## Task 10: Run build-only verification and independent review

**Objective:** Prove the configuration builds before touching live launchd state.

**Files:** No additional production files unless failures reveal a root cause.

**Step 1: Format changed files**

Run:

```bash
nix fmt
```

Review the diff and reject unrelated formatting changes.

**Step 2: Run focused checks**

Run:

```bash
nix build --no-link --show-trace .#checks.aarch64-darwin.emacs-daemon-configured-smoke
nix build --no-link --show-trace .#checks.aarch64-darwin.selection-batch-minimal-package-smoke
nix build --no-link --show-trace .#checks.aarch64-darwin.selection-batch-minimal-configured-smoke
```

Expected: all PASS.

**Step 3: Build watari without activation**

Run:

```bash
make build
```

Expected: `.#darwinConfigurations.watari.system` builds successfully. No switch occurs.

**Step 4: Evaluate Linux hosts and checks**

Run:

```bash
nix build --impure --keep-going --no-link --show-trace --system x86_64-linux \
  .#checks.x86_64-linux.emacs-daemon-configured-smoke \
  .#nixosConfigurations.lawliet.config.system.build.toplevel \
  .#nixosConfigurations.ryuk.config.system.build.toplevel \
  .#nixosConfigurations.rem.config.system.build.toplevel
```

Expected: PASS, or a documented builder-capability blocker unrelated to the code.

**Step 5: Inspect exact rendered launchd plist**

Evaluate/build the watari Home Manager generation and inspect the Emacs plist. Confirm:

- label: `org.nix-community.home.emacs`
- domain: `gui`
- stable ProgramArguments
- `RunAtLoad = true`
- `KeepAlive.Crashed = true`
- `KeepAlive.SuccessfulExit = false`
- no Emacs store path appears in plist

**Step 6: Review the diff**

Perform both spec-compliance and code-quality reviews. In particular, verify:

- No activation script kills Emacs.
- No empty alternate-editor fallback remains.
- No broad LaunchServices/TCC reset was added.
- No hard-coded username exists outside evaluated `home.homeDirectory`.
- Client app identity is unique.
- Darwin daemon starts via `.app` wrapper.
- Tests cover both platforms.

Do not commit unless the user separately asks for a commit.

---

## Task 11: Approval gate for watari canary activation

**Objective:** Activate only after the user has protected live editor state.

This is a separate, explicit approval gate. Build success does not authorize activation.

**Step 1: Present the canary summary**

Show:

- changed files
- all test/build results
- rendered launchd plist
- expected runtime transition
- rollback command/path

**Step 2: Ask the user to save or deliberately preserve every modified buffer**

Re-run:

```bash
emacsclient --eval '(mapcar #'buffer-name (seq-filter (lambda (b) (with-current-buffer b (buffer-modified-p))) (buffer-list)))'
```

Do not proceed while relevant modified buffers remain.

**Step 3: Ask exactly one activation decision**

Recommended choice: activate the built watari generation after buffers are safe.

Do not combine this with Dock replacement or commit approval.

---

## Task 12: Activate watari daemon canary

**Objective:** Transition from normal GUI Emacs to the managed launchd daemon without losing user data.

**Files:** Live system state only; no new source edits unless a verified defect appears.

**Step 1: Save session context**

Record:

- current file-visiting buffers
- selected project/workspace
- current Emacs PID
- current package path

Optionally use desktop/session persistence only if already configured; do not introduce it during canary activation.

**Step 2: Cleanly quit the normal GUI Emacs**

Use normal Emacs quit behavior after modified-buffer output is empty. Verify PID 17440 exits. Do not send SIGKILL.

**Step 3: Perform the approved nix-darwin switch**

Because privilege elevation may be required, the user runs:

```bash
nh darwin switch . -H watari
```

Expected:

- Home Manager installs the stable shim.
- `Emacs Client.app` is copied.
- launchd loads `org.nix-community.home.emacs`.
- daemon starts once.

**Step 4: Verify service state**

Run:

```bash
launchctl print "gui/$(id -u)/org.nix-community.home.emacs"
emacs-daemon-status
emacsclient --eval '(list :daemonp (daemonp) :pid (emacs-pid))'
```

Expected:

- loaded/running launchd agent
- `:daemonp t`
- one Emacs daemon PID

**Step 5: Create a frame through the shared entry point**

Run:

```bash
emacs-frame
```

Expected: one native GUI frame appears and remains attached to the daemon.

**Step 6: Verify package environment in the live daemon**

Run:

```bash
emacsclient --eval '(list
  :site-lisp (getenv "emacsWithPackages_siteLisp")
  :exec-path-from-shell (locate-library "exec-path-from-shell")
  :lsp-mode (locate-library "lsp-mode")
  :lean4-mode (locate-library "lean4-mode"))'
```

Expected: every path is non-nil and belongs to the intended Nix generation.

**Step 7: Verify Lean end-to-end**

Open the existing Lean file through `emacs-frame`, preserving its already-saved contents. Verify:

- `major-mode = lean4-mode`
- `lsp-mode = t`
- workspace root is `/Users/kaki/src/ladr-lean`
- workspace status reaches initialized
- no duplicate Lean server remains from the old GUI process

---

## Task 13: Prove generation-switch safety

**Objective:** Demonstrate that a Home Manager activation does not restart the running daemon.

**Step 1: Record daemon PID and create a disposable modified buffer**

Use a non-file test buffer with clearly disposable content, or a temporary file outside the repository. Do not use real work as the test payload.

Record:

```bash
emacsclient --eval '(emacs-pid)'
```

**Step 2: Re-run the same activation**

Run the already approved switch again without changing the plist.

Expected:

- Home Manager reports the launchd agent is already up to date.
- PID does not change.
- disposable modified buffer remains intact.

**Step 3: Build a package-generation-change canary without activation**

Change only a harmless derivation identity in a temporary worktree or disposable patch and build the candidate generation. Compare:

- launchd plist: unchanged
- stable shim target: changed

Do not activate the temporary package-change candidate unless separately approved.

**Step 4: Remove the disposable test state**

Delete only the temporary buffer/file after confirming the preservation property.

---

## Task 14: Approval gate for Dock migration

**Objective:** Switch user-facing GUI entry only after daemon operation is proven.

Present one decision:

- Recommended: remove the old Emacs Dock item and add `~/Applications/Home Manager Apps/Emacs Client.app`.
- Alternative: keep the old item temporarily during canary, with the explicit risk of accidentally launching a second non-daemon Emacs.

Do not modify the Dock without explicit approval.

After approval:

1. Remove only the existing Emacs Dock tile.
2. Add the exact copied `Emacs Client.app` path.
3. Leave LaunchServices globally intact.
4. Launch from Dock and verify it reaches the existing daemon PID.
5. Verify a second daemon/process is not created.

---

## Task 15: Linux runtime regression verification

**Objective:** Confirm the shared client abstraction does not degrade lawliet.

**Step 1: Activate Linux only through the normal separately approved host workflow**

No remote `nixos-rebuild switch` or Home Manager activation is implied by the plan. Obtain approval before live activation.

**Step 2: Verify systemd daemon behavior**

Run on lawliet during a graphical session:

```bash
systemctl --user status emacs.service
emacs-daemon-status
emacsclient --eval '(list :daemonp (daemonp) :pid (emacs-pid))'
```

Expected: enabled, active, `daemonp t`.

**Step 3: Verify Niri `Mod+E`**

Expected:

- It runs `emacs-frame`.
- It connects to the systemd-managed daemon.
- It does not create a standalone `--daemon` process.

**Step 4: Verify package visibility and Lean mode**

Use the same live daemon queries as watari.

---

## 4. Rollback plan

### Before live activation

No runtime rollback is needed. Revert only the source diff or select the previous plan state. The existing normal GUI Emacs remains running.

### If watari launchd daemon fails before opening files

1. Inspect, without deleting state:

```bash
launchctl print "gui/$(id -u)/org.nix-community.home.emacs"
emacs-daemon-status
```

2. Return to the prior nix-darwin generation using the normal generation rollback procedure.
3. Open the known-good copied app directly:

```bash
open "$HOME/Applications/Home Manager Apps/Emacs.app"
```

4. Do not rebuild the entire LaunchServices database.

### If a daemon frame works but Lean/LSP fails

1. Keep the daemon running to preserve buffers.
2. Capture `emacs-daemon-status`, `load-path`, `exec-path`, `ELAN_HOME`, and LSP logs.
3. Use the direct app only in a separate controlled comparison after saving buffers.
4. Fix the environment or init root cause, rebuild, and use `emacs-daemon-restart` only after its modified-buffer gate passes.

### If Home Manager activation unexpectedly attempts to restart Emacs

Abort activation before accepting any prompt that would terminate the editor. Treat this as a release-blocking defect in the stable-plist design. Do not work around it with automatic buffer saving or SIGKILL.

---

## 5. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Home Manager launchd update restarts daemon | Unsaved-buffer loss | Stable `~/.local/bin/emacs-daemon` in plist; byte-compare plist tests; live PID-preservation canary |
| Daemon starts with `window-system=nil` | PATH/Lean tools unavailable | Daemon-aware idempotent environment initializer and ERT coverage |
| First GUI frame lacks UI setup | Incorrect theme/frame behavior | Observe first-frame canary; move only proven frame-dependent code to `after-make-frame-functions` |
| `emacsclient -a ""` starts unmanaged daemon | Split lifecycle and wrong package | Remove empty alternate editor; start systemd/launchd explicitly |
| Client app conflicts with `org.gnu.Emacs` | Wrong LaunchServices target | Unique `dev.yus314.emacs-client` identifier |
| Shell-script app launcher behaves poorly on Apple Silicon | Launch failure/Rosetta behavior | Native Mach-O wrapper via `makeBinaryWrapper` |
| Package update leaves old daemon running | New config not immediately active | `emacs-daemon-status` reports generation drift; intentional safe restart command |
| Automated restart loses buffers | Data loss | No force mode; refuse on modified buffers; no activation-time kill |
| Finder document opening is assumed but unsupported | Files do not open | Scope initial client app to frame creation; test Apple Event/document handling separately before advertising it |
| Linux graphical target inactive | Daemon not started at SSH-only session | `emacs-frame` explicitly starts systemd service; graphical auto-start remains unchanged |

## 6. Explicit non-goals

- Do not rewrite the Emacs package build or replace `emacsWithPackagesFromUsePackage`.
- Do not manually add Nix store `site-lisp` paths in init as a fallback.
- Do not change `org.gnu.Emacs` on the upstream Emacs bundle.
- Do not reset the global LaunchServices database.
- Do not auto-save buffers during deployment.
- Do not automatically kill or restart Emacs during Home Manager activation.
- Do not add `mac-app-util` unless the native client-app experiment is invalidated.
- Do not commit, push, or activate without separate user authorization.

## 7. Decision and approval sequence

1. **Architecture approval:** This plan adopts managed daemon + managed client on all desktop platforms.
2. **Candidate review:** Review source diff, tests, rendered launchd plist, and rollback procedure.
3. **watari activation approval:** Save buffers and activate daemon canary.
4. **Dock migration approval:** Replace only the user-facing Dock entry after canary success.
5. **Linux activation approval:** Roll out shared `emacs-frame` to lawliet and then other Linux hosts.
6. **Commit approval:** Commit only after cross-platform verification and an explicit request.

Only one unresolved approval decision should be presented at a time.
