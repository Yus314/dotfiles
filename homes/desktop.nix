{ pkgs, ... }:
{
  imports = [
    ../applications/alacritty
    ../applications/kitty
    ../applications/vivaldi
    ../applications/google-chrome
    ../applications/qutebrowser
  ];
  home.packages = with pkgs; [
    zoom-us
    discord
    code-cursor
    slack
  ];
}
