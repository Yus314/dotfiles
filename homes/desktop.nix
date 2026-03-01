{ pkgs, ... }:
{
  imports = [
    # ../applications/calibre  # temporarily disabled: calibre 8.16.2 marked as broken
    ../applications/kitty
    ../applications/ghostty
    ../applications/google-chrome
    ../applications/zen-browser
  ];
  home.packages = with pkgs; [
    zoom-us
    discord
    code-cursor
    slack
    firefox
  ];
}
