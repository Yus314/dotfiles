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
  imports = [
    ../modules/nix
    ../applications/nix/buildMachines.nix
  ];
  programs.nix.target.system = true;

  nixpkgs.overlays = [
    emacs-overlay.overlays.default
    nur-packages.overlays.default
  ] ++ lib.attrValues self.overlays;

  nixpkgs.config.allowUnfree = true;

  environment.shells = [ pkgs.fish ];
  programs.fish.enable = true;
  users.users.${username}.shell = pkgs.bash;
}
