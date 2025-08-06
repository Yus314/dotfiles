{ pkgs, inputs, ... }:
{
  imports = [
    ../desktop.nix
    ../../applications/hyprland
    ../../applications/niri
    ../../applications/sway
    ../../applications/i3
    ../../applications/tofi
    ../../applications/foot
    ../../applications/waybar
    ../../applications/dunst
    ../../applications/rclone
    ../../applications/nyxt
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
    # Temporarily disabled due to CI issues
    # inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
