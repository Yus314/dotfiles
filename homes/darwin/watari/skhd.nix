{
  config,
  lib,
  pkgs,
  ...
}:
let
  activateApplication = pkgs.writeShellScript "omniwm-activate-application" ''
    set -eu

    bundle_id=$1
    /usr/bin/open -b "$bundle_id"

    attempt=0
    while [ "$attempt" -lt 50 ]; do
      if /usr/bin/osascript \
        -e 'on run argv' \
        -e 'set bundleId to item 1 of argv' \
        -e 'tell application "System Events"' \
        -e 'if not (exists (first application process whose bundle identifier is bundleId)) then error number 1' \
        -e 'set frontmost of (first application process whose bundle identifier is bundleId) to true' \
        -e 'end tell' \
        -e 'end run' \
        "$bundle_id" 2>/dev/null
      then
        exit 0
      fi

      attempt=$((attempt + 1))
      /bin/sleep 0.1
    done

    exit 1
  '';
  skhdSettings = ''
    # Launch or focus applications.
    alt - k [
        "moonlight" ~
        * : /usr/bin/osascript -e 'tell application id "com.mitchellh.ghostty" to new window'
    ]
    # Emacs Client exits after creating a frame, so do not wait for an app process.
    alt - e [
        "moonlight" ~
        * : /usr/bin/open -b dev.yus314.emacs-client
    ]
    alt - b [
        "moonlight" ~
        * : ${activateApplication} app.zen-browser.zen
    ]

    # Match Niri's launcher and close-window actions.
    # Wait for the triggering modifiers to be released before sending Command-Space.
    ctrl + shift + alt - return [
        "moonlight" ~
        * : /bin/sleep 0.2; /usr/bin/osascript -e 'tell application "System Events" to keystroke " " using command down'
    ]
    alt - q [
        "moonlight" ~
        * : /usr/bin/osascript -e 'tell application "System Events" to tell first application process whose frontmost is true to click button 1 of window 1'
    ]

    # Moonlight owns these navigation chords while frontmost.
    alt - d [
        "moonlight" ~
        * : ${pkgs.omniwm}/bin/omniwmctl command focus left
    ]
    alt - n [
        "moonlight" ~
        * : ${pkgs.omniwm}/bin/omniwmctl command focus right
    ]
    alt - s [
        "moonlight" ~
        * : ${pkgs.omniwm}/bin/omniwmctl command switch-workspace next
    ]
    alt - t [
        "moonlight" ~
        * : ${pkgs.omniwm}/bin/omniwmctl command switch-workspace prev
    ]

    # Preserve the qualified Moonlight-only Kana -> F16 -> C-j path.
    0x68 [
        "moonlight" : ${pkgs.skhd}/bin/skhd -k "f16"; /bin/sleep 0.05; ${pkgs.skhd}/bin/skhd -k "ctrl - j"
        * ~
    ]
  '';
  skhdConfig = pkgs.writeText "watari-skhd-focus-persistent" skhdSettings;
in
{
  # OmniWM has no arbitrary command bindings. Keep skhd narrowly scoped to
  # the Niri-style application launch and close-window shortcuts it lacks.
  services.skhd = {
    enable = lib.mkForce true;
    skhdConfig = lib.mkForce skhdSettings;
  };

  launchd.user.agents.skhd.serviceConfig = {
    ProgramArguments = lib.mkForce [
      "${config.services.skhd.package}/bin/skhd"
      "-c"
      "${skhdConfig}"
    ];
    StandardErrorPath = "/Users/kaki/.local/state/sunshine-rollout/focus-persistence/stderr.log";
    StandardOutPath = "/Users/kaki/.local/state/sunshine-rollout/focus-persistence/stdout.log";
  };
}
