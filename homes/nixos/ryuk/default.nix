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
    unstable
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
      extraSpecialArgs = {
        inherit nixpkgs;
        inherit system;
        inherit org-babel emacs-overlay;
      };
      backupFileExtension = "hm-backup";
    };
  };
}
