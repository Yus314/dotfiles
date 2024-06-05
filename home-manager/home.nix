{ config, pkgs, inputs, nur, ... }:
let
  #un = if pkgs.stdenv.isDarwin then "kakinumayuusuke" else "kaki";
  un = "kakinumayuusuke";
  hd = if pkgs.stdenv.isDarwin then "/Users/" else "/home/";

in {
  home = {
    username = un;
    homeDirectory = hd + un;
    stateVersion = "23.11";
    packages = with pkgs;
      [ cowsay bat eza tldr ] ++ (if pkgs.stdenv.isLinux then [
        xfce.thunar
        xfce.tumbler
        gscreenshot
      ] else
        [ ]);
  };
  imports = [ ./common ./macOS ];
  programs.gh = { enable = true; };
  programs.lazygit = { enable = true; };
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };
  programs.fzf = { enable = true; };

  #  programs.vivaldi = { enable = true; };
  programs.home-manager.enable = true;
}
