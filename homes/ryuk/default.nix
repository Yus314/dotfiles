{ inputs }:
let
  inherit (inputs)
    nixpkgs
    home-manager
    unstable
    xremap
    bizin-gothic-discord
    ;
in
nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    ./lab-main-configuration.nix
    home-manager.nixosModules.home-manager
  ];
  specialArgs = {
    unstable = import unstable {
      sysmet = "x86_64-linux";
      config.allowUnfree = true;
    };
    inherit xremap;
    inherit bizin-gothic-discord;
  };
}
