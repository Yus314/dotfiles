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
    mcp-servers.url = "github:natsukium/mcp-servers-nix";
    mcp-servers.inputs.nixpkgs.follows = "nixpkgs";
    claude-desktop.url = "github:k3d3/claude-desktop-linux-flake";
    claude-desktop.inputs.nixpkgs.follows = "nixpkgs";
    niri.url = "github:sodiboo/niri-flake";
    niri.inputs.nixpkgs.follows = "nixpkgs";
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
          system = "aarch64-darwin";
        };
        lawliet = {
          system = "x86_64-linux";
        };
        ryuk = {
          system = "x86_64-linux";
        };
        rem = {
          system = "x86_64-linux";
        };
      };

      flake = {
        overlays = import ./overlays { inherit inputs; } // {
          custom-packages = import ./pkgs;
        };
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
          };
          pre-commit = {
            check.enable = true;
            settings = {
              src = ./.;
              hooks = {
                nil.enable = true;
                lua-ls = {
                  enable = true;
                  excludes = [
                    "applications/neovim/.*\\.lua$"
                  ];
                };
                tflint.enable = true;
                shellcheck.enable = true;
                biome.enable = true;
                yamllint = {
                  enable = true;
                  excludes = [
                    "secrets/default.yaml"
                    "secrets.yaml"
                  ];
                  settings.configData = "{rules: {document-start: {present: false}}}";
                };
                typos = {
                  enable = true;
                  excludes = [
                    "secrets.yaml"
                    "secrets/defualt.yaml"
                    "applications/neovim/lua/plugins/skkeleton.lua"
                    "applications/neovim/SKK-JISYO.L"
                  ];
                  settings.configPath = "typos.toml";
                };
                check-toml.enable = true;
                treefmt.enable = true;
                detect-private-keys.enable = true;
                end-of-file-fixer.enable = true;
                trim-trailing-whitespace.enable = true;
                fix-byte-order-marker.enable = true;
                actionlint.enable = true;
              };
            };
          };
          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              stylua.enable = true;
              terraform.enable = true;
              shfmt.enable = true;
              biome.enable = true;
              yamlfmt.enable = true;
              taplo.enable = true;
            };
          };
          devShells = {
            default = pkgs.mkShell {
              packages = with pkgs; [
                nix-fast-build
                sops
                qmk
                (terraform.withPlugins (p: [
                  p.cloudflare
                  p.external
                  p.github
                  p.null
                  p.sops
                  p.oci
                ]))
                cf-terraforming
              ];
              shellHook = config.pre-commit.installationScript;
            };
          };
        };
    };
}
