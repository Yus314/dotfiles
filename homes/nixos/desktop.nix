{ pkgs, inputs, ... }:
{
  imports = [
    ../desktop.nix
    ../../applications/hyprland
    ../../applications/niri
    ../../applications/sway
    ../../applications/swww
    #../../applications/spotlight-downloader
    ../../applications/i3
    ../../applications/tofi
    ../../applications/foot
    ../../applications/waybar
    ../../applications/dunst
    ../../applications/rclone
    ../../applications/nyxt
    ../../applications/fcitx5-cskk
  ];
  home.packages = with pkgs; [
    xfce.thunar
    xfce.tumbler
    sshfs
    gvfs
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
