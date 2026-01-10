{
  description = "A simple NixOS flakes";

  inputs = {
    nixpkgs.url = "git+https://github.com/nixos/nixpkgs?shallow=1&ref=nixos-unstable";
    nixpkgs-stable.url = "git+https://github.com/nixos/nixpkgs?shallow=1&ref=nixos-24.05";

    claude-desktop.url = "github:k3d3/claude-desktop-linux-flake";
    disko.url = "github:nix-community/disko";
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks.url = "github:cachix/git-hooks.nix";
    home-manager.url = "github:nix-community/home-manager";
    impermanence.url = "github:nix-community/impermanence";
    mcp-servers.url = "github:natsukium/mcp-servers-nix";
    niri.url = "github:sodiboo/niri-flake";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nur-packages.url = "github:Yus314/nur-packages";
    org-babel.url = "github:emacs-twist/org-babel";
    sops-nix.url = "github:Mic92/sops-nix";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    xremap.url = "github:xremap/nix-flake";
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # use in follows
    flake-utils.url = "github:numtide/flake-utils";

    claude-desktop.inputs.nixpkgs.follows = "nixpkgs";
    claude-desktop.inputs.flake-utils.follows = "flake-utils";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    emacs-overlay.inputs.nixpkgs-stable.follows = "nixpkgs-stable";
    emacs-overlay.inputs.nixpkgs.follows = "nixpkgs";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    git-hooks.inputs.flake-compat.follows = "";
    git-hooks.inputs.gitignore.follows = "";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    mcp-servers.inputs.nixpkgs.follows = "nixpkgs";
    niri.inputs.niri-stable.follows = "";
    niri.inputs.niri-unstable.follows = "";
    niri.inputs.nixpkgs-stable.follows = "nixpkgs-stable";
    niri.inputs.nixpkgs.follows = "nixpkgs";
    niri.inputs.xwayland-satellite-stable.follows = "";
    niri.inputs.xwayland-satellite-unstable.follows = "";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nur-packages.inputs.nixpkgs.follows = "nixpkgs";
    xremap.inputs.nixpkgs.follows = "nixpkgs";
    xremap.inputs.flake-parts.follows = "flake-parts";

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
            tf-wrapper = pkgs.tf-wrapper;
            adb-mcp = pkgs.adb-mcp;
            # LINE = pkgs.LINE;
          };
          pre-commit = {
            check.enable = true;
            settings = {
              src = ./.;
              hooks = {
                nil.enable = true;
                # lua-ls disabled: Neovim configurations are validated by Neovim runtime
                # lua-ls.enable = true;
                # tflint disabled: Terraform versions are managed by Nix
                # tflint.enable = true;
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
                    "secrets/default.yaml"
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
            settings = {
              global = {
                excludes = [
                  "secrets/*"
                  "**/secrets.yaml"
                ];
              };
            };
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
                  p.cloudflare_cloudflare
                  p.hashicorp_external
                  p.integrations_github
                  p.hashicorp_null
                  p.carlpett_sops
                  p.oracle_oci
                ]))
                cf-terraforming
              ];
              shellHook = config.pre-commit.installationScript;
            };
          };
        };
    };
}
