{ inputs, specialArgs, ... }:
let
  inherit (inputs)
    nixpkgs
    home-manager
    unstable
    xremap
    org-babel
    emacs-overlay
    ;
  inherit (specialArgs) username;
  system = "x86_64-linux";
in
{
  imports = [
    ../common.nix
  ];
  home-manager = {
    users.${username} = {
      imports = [ ../desktop.nix ];
    };
    extraSpecialArgs = {
      inherit nixpkgs;
      inherit system;
      inherit org-babel emacs-overlay;
    };
    backupFileExtension = "hm-backup";
  };
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
