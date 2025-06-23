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
    sops-nix
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
  #modules = [
  #  home-manager.nixosModules.home-manager
  #  {
  home-manager = {
    users.${username} = {
      imports = [
        # ../../../home-manager
        ../desktop.nix
      ];
    };
    extraSpecialArgs = {
      inherit nixpkgs;
      inherit system;
      inherit emacs-overlay;
    };
    backupFileExtension = "hm-backup";

  };
  #   }
  #  sops-nix.nixosModules.sops
  #];
  # specialArgs = {
  #   inherit emacs-overlay;
  #   inherit org-babel;
  #   # inherit xremap;
  #   nixpkgs = import nixpkgs {
  #     system = "x86_64-linux";
  #   };
  # };

}
