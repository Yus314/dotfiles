{
  inputs,
  lib,
  pkgs,
  specialArgs,
  self,
  ...
}:
let
  inherit (inputs) emacs-overlay nur-packages;
  inherit (specialArgs) username;
in
{
  nixpkgs.overlays = [
    emacs-overlay.overlays.default
    nur-packages.overlays.default
  ] ++ lib.attrValues self.overlays;

  nixpkgs.config.allowUnfree = true;

  nix.settings.trusted-users = [
    "root"
    "@wheel"
    "@admin"
  ];

  environment.shells = [ pkgs.fish ];
  programs.fish.enable = true;
  users.users.${username}.shell = pkgs.fish;
}
