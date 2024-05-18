{
  config,
  pkgs,
  inputs,
  ...
}: let
  un =
    if pkgs.stdenv.isDarwin
    then "kakinumayuusuke"
    else "kaki";
  hd =
    if pkgs.stdenv.isDarwin
    then "/Users/"
    else "/home/";
in {
  home = rec {
    username = un;
    homeDirectory = hd + un;
    stateVersion = "23.11";
    packages = with pkgs; [
      cowsay
      bat
      eza
      tldr
      alejandra
      nodePackages.prettier
    ];
  };
  imports = [
    inputs.nixvim.homeManagerModules.nixvim
    ./neovim/neovim.nix
    ./zsh.nix
    ./alacritty.nix
    ./git.nix
  ];
  programs.gh = {
    enable = true;
  };
  programs.lazygit = {
    enable = true;
  };

  #programs.vivaldi = {
  #enable = true;
  #};
  programs.home-manager.enable = true;
}
