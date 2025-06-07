{ inputs }:
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
  #xremap = nixpkgs.callPackage .../../xremap.nix { };
in

nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    ../../configuration.nix
    home-manager.nixosModules.home-manager
    {
      home-manager = {
        users.kaki = import ../../home-manager;
        extraSpecialArgs = {
          inherit nixpkgs;
          inherit system;
          inherit emacs-overlay;
        };
      };
    }
    sops-nix.nixosModules.sops
  ];
  specialArgs = {
    #            unstable = import unstable {
    #             system = "x86_64-linux";
    #             config.allowUnfree = true;
    #           };
    inherit emacs-overlay;
    inherit org-babel;
    # inherit xremap;
    nixpkgs = import nixpkgs {
      system = "x86_64-linux";
    };
  };

}
