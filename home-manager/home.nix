{
  config,
  pkgs,
  inputs,
  ...
}: let
in {
  home = rec {
    #username = "kakinumayuusuke";
    username = "kaki";
    #homeDirectory = "/Users/${username}";
    homeDirectory = "/home/${username}";
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
    ./neovim.nix
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
