{ config, pkgs, inputs, nur, ... }:
let
  un = if pkgs.stdenv.isDarwin then "kakinumayuusuke" else "kaki";
  hd = if pkgs.stdenv.isDarwin then "/Users/" else "/home/";

in {
  home = {
    username = un;
    homeDirectory = hd + un;
    stateVersion = "23.11";
    packages = with pkgs; [
      cowsay
      bat
      eza
      tldr
      xfce.thunar
      xfce.tumbler
      gscreenshot
    ];
  };
  imports = [
    ./zsh.nix
    ./alacritty.nix
    ./git.nix
    ./neovim/neovim.nix
    ./tmux.nix
    ./i3.nix
  ];
  programs.gh = { enable = true; };
  programs.lazygit = { enable = true; };
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };
  programs.fzf = { enable = true; };

  programs.vivaldi = { enable = true; };
  programs.home-manager.enable = true;
}
