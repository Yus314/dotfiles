{ inputs }:
let
  inherit (inputs)
    nixpkgs
    home-manager
    unstable
    nix-homebrew
    brew-nix
    emacs-overlay
    org-babel
nix-darwin
  ;
  #bizin-gothic-discord = nixpkgs.callPackage ../../bizin.nix {};
in
nix-darwin.lib.darwinSystem {
  system = "aarch64-darwin";
  modules = [
    ../../darwin-configuration.nix
    home-manager.darwinModules.home-manager
    #{
    #  home-manager = {
    #  extraSpecialArgs = {
#	inherit  bizin-gothic-discord;
 #     };
#	};
#  }
    nix-homebrew.darwinModules.nix-homebrew
    brew-nix.darwinModules.default
  ];
  specialArgs = {
    unstable = import unstable {
      sysmet = "aarch64-darwin";
      config.allowUnfree = true;
    };
    inherit emacs-overlay;
    inherit org-babel;
    inherit brew-nix;
    inherit bizin-gothic-discord;
  };
}
