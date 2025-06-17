{ inputs, ... }:
let
  inherit (inputs)
    nixpkgs
    home-manager
    unstable
    xremap
    ;
in
{
  imports = [
    ../common.nix
  ];
  #  system = "x86_64-linux";
  #  modules = [
  #    ./lab-sub-configuration.nix
  #    home-manager.nixosModules.home-manager
  #  ];
  #  specialArgs = {
  #    unstable = import unstable {
  #      sysmet = "x86_64-linux";
  #      config.allowUnfree = true;
  #    };
  #    inherit xremap;
  #  };
}
