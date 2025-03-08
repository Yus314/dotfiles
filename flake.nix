{
  description = "A simple NixOS flakes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-24.05-darwin";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    wezterm = {
      url = "github:wez/wezterm?dir=nix";
    };
    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
    };
    org-babel.url = "github:emacs-twist/org-babel";
    sops-nix.url = "github:Mic92/sops-nix";
    impermanence.url = "github:nix-community/impermanence";
  };
  outputs =
    {
      nixpkgs,
      unstable,
      nixpkgs-darwin,
      nixos-hardware,
      home-manager,
      nix-darwin,
      nix-homebrew,
      homebrew-core,
      homebrew-cask,
      wezterm,
      emacs-overlay,
      org-babel,
      sops-nix,
      ...
    }:
    let
      tmp_pkgs = import nixpkgs { system = "x86_64-linux"; };
      bizin-gothic-discord = tmp_pkgs.callPackage ./bizin.nix { };
      xremap = tmp_pkgs.callPackage ./xremap.nix { };
    in
    {
      packages.x86_64-linux.default = tmp_pkgs.callPackage ./bizin.nix { };
      nixosConfigurations = {
        home = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./configuration.nix
            home-manager.nixosModules.home-manager
            sops-nix.nixosModules.sops
          ];
          specialArgs = {
            unstable = import unstable {
              system = "x86_64-linux";
              config.allowUnfree = true;
            };
            inherit emacs-overlay;
            inherit org-babel;
            inherit xremap;
          };
        };
        lab-main = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./lab-main-configuration.nix
            home-manager.nixosModules.home-manager
          ];
          specialArgs = {
            unstable = import unstable {
              system = "x86_64-linux";
              config.allowUnfree = true;
            };
            inherit wezterm;
            inherit emacs-overlay;
            inherit org-babel;
            inherit bizin-gothic-discord;
          };
        };
        lab-sub = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./lab-sub-configuration.nix
            home-manager.nixosModules.home-manager
          ];
          # specialArgs = {
          # inherit allowed-unfree-packages;
          # };
        };
      };
      darwinConfigurations."kakinumayuusukenoMacBook-Air" = nix-darwin.lib.darwinSystem {
        system = "aaarch64-darwin";
        modules = [
          ./darwin-configuration.nix
          home-manager.darwinModules.home-manager
          nix-homebrew.darwinModules.nix-homebrew
        ];
        specialArgs = {
          inherit unstable;
          inherit emacs-overlay;
          inherit org-babel;
        };
      };
    };
}
