{
  description = "A simple NixOS flakes";

  inputs = {
    nixpkgs.url = "git+https://github.com/nixos/nixpkgs?shallow=1&ref=nixos-unstable";
    nixpkgs-stable.url = "git+https://github.com/nixos/nixpkgs?shallow=1&ref=nixos-24.05";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-24.11-darwin";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
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
    flake-parts.url = "github:hercules-ci/flake-parts";
    cachix-deploy-flake.url = "github:cachix/cachix-deploy-flake";
    brew-nix = {
      # for local testing via `nix flake check` while developing
      #url = "path:../";
      url = "github:BatteredBunny/brew-nix";
      inputs.nix-darwin.follows = "nix-darwin";
      inputs.brew-api.follows = "brew-api";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };
  };
  outputs =
    {
      nixpkgs,
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
      flake-parts,
      brew-nix,
      brew-api,
      ...
    }@inputs:
    #let
    #  tmp_pkgs = import nixpkgs { system = "x86_64-linux"; };
    #  tmp_pkgs2 = import nixpkgs { system = "aarch64-darwin"; };
    #  bizin-gothic-discord = tmp_pkgs.callPackage ./bizin.nix { };
    #  bizin-gothic-discord2 = tmp_pkgs2.callPackage ./bizin.nix { };
    #  xremap = tmp_pkgs.callPackage ./xremap.nix { };
    #in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];

      #packages.x86_64-linux.default = tmp_pkgs.callPackage ./bizin.nix { };
      flake = {
        nixosConfigurations = {
          watari = import ./homes/watari { inherit inputs; };
        };
      };
      #nixosConfigurations = {

      # lab-main = nixpkgs.lib.nixosSystem {
      #   system = "x86_64-linux";
      #   modules = [
      #     ./lab-main-configuration.nix
      #     home-manager.nixosModules.home-manager
      #   ];
      #   specialArgs = {
      #   unstable = import unstable {
      #     system = "x86_64-linux";
      #     config.allowUnfree = true;
      #   };
      #     inherit emacs-overlay;
      #     inherit org-babel;
      # inherit xremap;
      #inherit bizin-gothic-discord;
      #  };
      #};
      #lab-sub = nixpkgs.lib.nixosSystem {
      #  system = "x86_64-linux";
      #  modules = [
      #    ./lab-sub-configuration.nix
      #    home-manager.nixosModules.home-manager
      #  ];
      # specialArgs = {
      # inherit allowed-unfree-packages;
      # };
      #};
      #};
      #darwinConfigurations."KakinumanoMacBook-Air" = nix-darwin.lib.darwinSystem {
      #  system = "aaarch64-darwin";
      #  modules = [
      #    ./darwin-configuration.nix
      #    home-manager.darwinModules.home-manager
      #    nix-homebrew.darwinModules.nix-homebrew
      #    brew-nix.darwinModules.default
      #  ];
      #  specialArgs = {
      #    #    unstable = import unstable {
      #    #      system = "aarch64-darwin";
      #    #      config.allowUnfree = true;
      #    #    };
      #    inherit emacs-overlay;
      #    inherit org-babel;
      #    inherit brew-nix;
      #    #  bizin-gothic-discord = bizin-gothic-discord2;
      #  };
      #};
    };
}
