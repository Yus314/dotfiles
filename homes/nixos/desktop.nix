{ pkgs, inputs, ... }:
{
  imports = [
    ../desktop.nix
    ../../applications/niri
    ../../applications/obsidian
    ../../applications/swww
    ../../applications/spotlight-downloader
    ../../applications/tofi
    ../../applications/waybar
    ../../applications/dunst
    ../../applications/rclone
    ../../applications/nyxt
    ../../applications/fcitx5-cskk
    ../../applications/darkman
    #../../applications/obs-studio
  ];
  home.packages = with pkgs; [
    thunar
    tumbler
    sshfs
    gvfs
    gscreenshot
    wl-clipboard
    #swaylock
    #swayidle
    wlogout
    #krita
    rnote
    scrcpy
  ];
}
