{
  pkgs,
  inputs,
  ...
}:
let
  inherit (inputs) emacs-overlay;
in
{
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = [
    pkgs.vim
    pkgs.pinentry_mac
    pkgs.cloudflared
  ];
  ids.gids.nixbld = 350;
  system.primaryUser = "kaki";

  networking.hostName = "watari";

  fonts.packages = [
    pkgs.bizin-gothic-nf
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
    package = pkgs.karabiner-elements.overrideAttrs (old: {
      version = "14.13.0";

      src = pkgs.fetchurl {
        inherit (old.src) url;
        hash = "sha256-gmJwoht/Tfm5qMecmq1N6PSAIfWOqsvuHU8VDJY8bLw=";
      };
    });
  };
}
