{
  inputs,
  lib,
  pkgs,
  specialArgs,
  self,
  ...
}:
let
  inherit (inputs)
    emacs-overlay
    nur-packages
    firefox-addons
    brew-nix
    ;
  inherit (specialArgs) username;
in
{
  imports = [
    ../modules/nix
    ../applications/nix/buildMachines.nix
  ];
  programs.nix.target.system = true;

  nixpkgs.overlays = [
    emacs-overlay.overlays.default
    nur-packages.overlays.default
    firefox-addons.overlays.default
    brew-nix.overlays.default
  ]
  ++ lib.attrValues self.overlays;

  nixpkgs.config.allowUnfree = true;

  # for Spotlight Downloader
  nixpkgs.config.permittedInsecurePackages = [
    "dotnet-sdk-6.0.428"
    "dotnet-runtime-6.0.36"
  ];

  environment.shells = [ pkgs.fish ];
  programs.fish.enable = true;
  #users.users.${username}.shell = pkgs.fish;

  nix.gc = {
    automatic = true;
    options = "--delete-older-than 7d";
  }
  // lib.optionalAttrs pkgs.stdenv.isLinux { dates = "weekly"; }
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    interval = {
      Weekday = 0;
      Hour = 0;
      Minute = 0;
    };
  };

  nix.optimise.automatic = true;

  nix.channel.enable = false;
}
