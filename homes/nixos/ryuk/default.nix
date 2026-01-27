{
  inputs,
  pkgs,
  specialArgs,
  ...
}:
let
  inherit (inputs)
    nixpkgs
    home-manager
    sops-nix
    emacs-overlay
    org-babel
    ;
  system = "x86_64-linux";
  inherit (specialArgs) username;
in
{
  imports = [
    home-manager.nixosModules.home-manager
    sops-nix.nixosModules.sops
    ../common.nix
  ];
  home-manager = {
    users.${username} = {
      imports = [ ../desktop.nix ];
    };
    extraSpecialArgs = {
      inherit inputs;
      inherit nixpkgs;
      inherit system;
      inherit emacs-overlay;
      inherit org-babel;
    };
    backupFileExtension = "hm-backup";
  };
}
