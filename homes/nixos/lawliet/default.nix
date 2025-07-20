{
  inputs,
  pkgs,
  specialArgs,
  ...
}:
let
  inherit (inputs)
    org-babel
    nixpkgs
    home-manager
    emacs-overlay
    ;

  system = "x86_64-linux";
  inherit (specialArgs) username;
in
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    ../common.nix
  ];
  home-manager = {
    users.${username} = {
      imports = [
        ../desktop.nix
      ];
      home.packages = with pkgs; [ bluetui ];
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
