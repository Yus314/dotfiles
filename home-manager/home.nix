{ config, pkgs, inputs, nur, ... }:
let
  un = if pkgs.stdenv.isDarwin then "kakinumayuusuke" else "kaki";
  hd = if pkgs.stdenv.isDarwin then "/Users/" else "/home/";

in {
  home = {
    username = un;
    homeDirectory = hd + un;
    stateVersion = "23.11";
    packages = with pkgs; [ cowsay bat eza tldr ];
  };
  imports = [ ./zsh.nix ./alacritty.nix ./git.nix ./neovim/neovim.nix ];
  programs.gh = { enable = true; };
  programs.lazygit = { enable = true; };
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };
  programs.fzf = { enable = true; };

  #programs.vivaldi = {
  #enable = true;
  #};
  programs.chromium = {
    enable = false;
    #package = if pkgs.stdenv.isLinux then pkgs.vivaldi else inputs.nur.vivaldi;
    #package = nurpkgs.vivaldi-bin;
  };
  programs.home-manager.enable = true;
}
