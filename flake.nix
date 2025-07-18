{
  description = "A simple NixOS flakes";

  inputs = {
    nixpkgs.url = "git+https://github.com/nixos/nixpkgs?shallow=1&ref=nixos-unstable";
    nixpkgs-stable.url = "git+https://github.com/nixos/nixpkgs?shallow=1&ref=nixos-24.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    emacs-overlay.url = "github:nix-community/emacs-overlay";

    org-babel.url = "github:emacs-twist/org-babel";
    sops-nix.url = "github:Mic92/sops-nix";
    impermanence.url = "github:nix-community/impermanence";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks.url = "github:cachix/git-hooks.nix";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    nur-packages.url = "github:Yus314/nur-packages";
    nur-packages.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    xremap.url = "github:xremap/nix-flake";
  };
  outputs =
    {
      self,
      flake-parts,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      imports = [
        ./flake-module.nix
        inputs.git-hooks.flakeModule
        inputs.treefmt-nix.flakeModule
      ];
      hosts = {
        watari = {
          system = "x86_64-linux";
        };
        lawliet = {
          system = "x86_64-linux";
          #system = "aarch64-darwin";
        };
        ryuk = {
          system = "x86_64-linux";
        };
        rem = {
          system = "x86_64-linux";
        };
      };

      flake = {
        # overlays = import ./overlays { inherit inputs; };
      };

      perSystem =
        {
          config,
          pkgs,
          system,
          ...
        }:
        {
          _module.args.pkgs = import self.inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ self.inputs.nur-packages.overlays.default ] ++ builtins.attrValues self.overlays;
          };
          packages = rec {
            # cskk = pkgs.callPackage ./pkgs/cskk { };
            #fcitx5-cskk = pkgs.libsForQt5.callPackage ./pkgs/fcitx5-cskk { inherit cskk; };
          };
          pre-commit = {
            check.enable = true;
            settings = {
              src = ./.;
              hooks = {
                nil.enable = true;
                shellcheck.enable = true;
                treefmt.enable = true;
              };
            };
          };
          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              biome.enable = true;
              nixfmt.enable = true;
              shfmt.enable = true;
              stylua.enable = true;
              taplo.enable = true;
              terraform.enable = true;
              yamlfmt.enable = true;
            };
          };
          devShells = {
            default = pkgs.mkShell {
              packages = with pkgs; [
                nix-fast-build
                sops
                go-task
                (terraform.withPlugins (p: [
                  p.cloudflare
                  p.external
                  p.github
                  p.null
                  p.sops
                ]))
                cf-terraforming
              ];
              shellHook = config.pre-commit.installationScript;
            };
          };
        };
    };
}
