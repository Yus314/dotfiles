{ inputs, ... }:
let
  inherit (inputs)
    nixpkgs
    home-manager
    unstable
    sops-nix
    emacs-overlay
    org-babel
    ;
  system = "x86_64-linux";

in
{
  imports = [
    home-manager.nixosModules.home-manager
    sops-nix.nixosModules.sops
  ];
  #    home-manager = {
  #       users.kaki = import ../../home-manager;
  #       extraSpecialArgs = {
  #         inherit nixpkgs;
  #         inherit system;
  #         inherit org-babel emacs-overlay;
  #       };
  #     };
  #   }
  # specialArgs = {
  #   unstable = import unstable {
  #     sysmet = "x86_64-linux";
  #     config.allowUnfree = true;
  #   };
}
