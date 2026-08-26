{
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
in
{
  # OmniWM has no arbitrary command bindings. Keep skhd narrowly scoped to
  # the Niri-style application launch and close-window shortcuts it lacks.
  services.skhd = {
    enable = lib.mkForce true;
    skhdConfig = lib.mkForce ''
      # Launch or focus applications.
      alt - k : /usr/bin/osascript -e 'tell application id "com.mitchellh.ghostty" to new window'
      alt - e : ${activateApplication} org.gnu.Emacs
      alt - b : ${activateApplication} app.zen-browser.zen

      # Match Niri's launcher and close-window actions.
      ctrl + shift + alt - return : /usr/bin/osascript -e 'tell application "System Events" to keystroke " " using command down'
      alt - q : /usr/bin/osascript -e 'tell application "System Events" to tell first application process whose frontmost is true to click button 1 of window 1'
    '';
  };
}
