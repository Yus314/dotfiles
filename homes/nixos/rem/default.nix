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
    home-manager.nixosModules.home-manager
    ../common.nix
  ];
  home-manager = {
    users.${username} = {
      imports = [ ../desktop.nix ];
    };
    extraSpecialArgs = {
      inherit nixpkgs;
      inherit system;
      inherit emacs-overlay;
      inherit org-babel;

    };
    backupFileExtension = "hm-backup";
  };
}
