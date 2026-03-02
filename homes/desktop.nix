{ pkgs, ... }:
{
  imports = [
    # ../applications/calibre
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
