{ pkgs, ... }:
{
  imports = [
    ../desktop.nix
    ../../applications/hyprland
    ../../applications/sway
    ../../applications/i3
    ../../applications/tofi
    ../../applications/foot
  ];
  home.packages = with pkgs; [
    xfce.thunar
    xfce.tumbler
    gscreenshot
    waybar
    wl-clipboard
    #swaylock
    #swayidle
    wlogout
    pinta
    nyxt
  ];
  programs.waybar = {
    enable = false;
    systemd.enable = true;
  };
}
