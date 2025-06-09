{ pkgs, ... }:
let
  i3 = import ./i3.nix;
  packages = import ./packages.nix;
  sway = import ./sway.nix;
  hyprland = import ./hyprland.nix;
  waybar = import ./waybar.nix;
  browser = import ./browser.nix;
  foot = import ./foot.nix;
  tofi = import ./tofi.nix;
  #    ../../../Service/emacs
in

[
  i3
  packages
  sway
  hyprland
  waybar
  browser
  foot
  tofi
]
#}
