{ pkgs, ... }:
{
  imports = [
    ../desktop.nix
    ../../applications/hyprland
    ../../applications/sway
    ../../applications/i3
    ../../applications/tofi
    ../../applications/foot
    ../../applications/waybar
  ];
  home.packages = with pkgs; [
    xfce.thunar
    xfce.tumbler
    gscreenshot
    wl-clipboard
    #swaylock
    #swayidle
    wlogout
    pinta
    nyxt
  ];
}
