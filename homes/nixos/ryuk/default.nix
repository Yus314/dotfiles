{ inputs,... }:
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

in
 {
  modules = [
    ../../systems/nixos/ryuk
    home-manager.nixosModules.home-manager
    {
      home-manager = {
        users.kaki = import ../../home-manager;
        extraSpecialArgs = {
          inherit nixpkgs;
          inherit system;
          inherit org-babel emacs-overlay;
        };
      };
    }
    sops-nix.nixosModules.sops
  ];
  specialArgs = {
    unstable = import unstable {
      sysmet = "x86_64-linux";
      config.allowUnfree = true;
    };
  };
}
