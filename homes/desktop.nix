{ pkgs, ... }:
{
  imports = [
    ../applications/alacritty
    ../applications/kitty
    ../applications/ghostty
    ../applications/vivaldi
    ../applications/google-chrome
    ../applications/qutebrowser
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
