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
  username = "kaki";
in

{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
  ];
  #modules = [
  #  home-manager.nixosModules.home-manager
  #  {
  home-manager = {
    users.kaki = import ../../../home-manager;
    extraSpecialArgs = {
      inherit nixpkgs;
      inherit system;
      inherit emacs-overlay;
    };
    backupFileExtension = "hm-backup";
    extraSpecialArgs = {
      inherit org-babel;
    };

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
