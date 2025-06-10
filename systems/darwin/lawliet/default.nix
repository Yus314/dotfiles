{
  pkgs,
  inputs,
  ...
}:
let
  bizin-gothic-discord = pkgs.callPackage ../../../pkgs/bizin {};
  inherit (inputs) emacs-overlay;
  in
{
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = [
    pkgs.vim
    pkgs.gnupg
    pkgs.pinentry_mac
    pkgs.cloudflared
    #pkgs.brewCasks.dropbox
    #pkgs.brewCasks.aquaskk
    #pkgs.brewCasks.zoom
  ];
   ids.gids.nixbld = 350;
   system.primaryUser = "kaki";
   
  # Auto upgrade nix package and the daemon service.
  nix.package = pkgs.nix;
 # nixpkgs.hostPlatform = "aarch64-darwin";
fonts.packages =
[
bizin-gothic-discord
];

  imports = [
    ../common.nix
    ../desktop.nix
  ];

  #fonts.font = with pkgs; [
  #  noto-fonts-cjk-serif
  #  noto-fonts-cjk-sans
  #  noto-fonts-emoji
  #  nerdfonts
  #];
  #home-manager.users.kotsu = import ./home-manager/home.nix;
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
  programs.gnupg = {
    agent = {
      enable = true;
    };
  };
   services.karabiner-elements = {
     enable = true;
     };
  #nix-homebrew = {
   # enable = true;
   # enableRosetta = true;
   # user = "kotsu";
  #};
}
