{
  config,
  lib,
  specialArgs,
  ...
}:
let
  inherit (specialArgs) username;
  homeManagerApps = "/Users/${username}/Applications/Home Manager Apps";
  emacsPackage = config.home-manager.users.${username}.programs.emacs.finalPackage;
in
{
  # OmniWM has no arbitrary command bindings. Keep skhd narrowly scoped to
  # the Niri-style application launch and close-window shortcuts it lacks.
  services.skhd = {
    enable = lib.mkForce true;
    skhdConfig = lib.mkForce ''
      # Launch or focus applications.
      alt - k : /usr/bin/open -n '${homeManagerApps}/Ghostty.app'
      alt - e : ${lib.getExe' emacsPackage "emacsclient"} -c -a ""
      alt - b : /usr/bin/open '${homeManagerApps}/Zen Browser (Beta).app'

      # Match Niri's launcher and close-window actions.
      ctrl + shift + alt - return : /usr/bin/osascript -e 'tell application "System Events" to keystroke " " using command down'
      alt - q : /usr/bin/osascript -e 'tell application "System Events" to tell first application process whose frontmost is true to click button 1 of window 1'
    '';
  };
}
