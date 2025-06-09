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
   system.primaryUser = "kotsu";
   
  # Auto upgrade nix package and the daemon service.
  nix.package = pkgs.nix;
  nixpkgs.hostPlatform = "aarch64-darwin";
  security.pam.services.sudo_local.touchIdAuth = true;
nixpkgs.config.allowBroken = true;
nixpkgs.overlays = [
(self: super: {
karabiner-elements = super.karabiner-elements.overrideAttrs (old: {
version = "14.13.0";

    src = super.fetchurl {
      inherit (old.src) url;
      hash = "sha256-gmJwoht/Tfm5qMecmq1N6PSAIfWOqsvuHU8VDJY8bLw=";
    };
				dontFixup = true;
  });
})
];
fonts.packages =
[
bizin-gothic-discord
];

  imports = [
    ../../../home-manager/macOS/yabai.nix
    ../../../home-manager/macOS/shkd.nix
    ../common.nix
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
