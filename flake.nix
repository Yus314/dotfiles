{
  description = "A simple NixOS flakes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-24.05-darwin";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
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
  };
  outputs =
    inputs:
    let
      allowed-unfree-packages = [ "vivaldi" ];
    in
    {
      nixosConfigurations = {
        myNixOS = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./configuration.nix
            inputs.home-manager.nixosModules.home-manager
          ];
          specialArgs = {
            inherit allowed-unfree-packages;
          };
        };
      };
      homeConfigurations = {
        myHome = inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = import inputs.nixpkgs {
            system = "x86_64-linux";
            #system = "aarch64-darwin";
            config.allowUnfree = true;
          };
          extraSpecialArgs = {
            inherit inputs;
          };
          modules = [ ./home-manager/home-nixos.nix ];
        };
      };
      darwinConfigurations."kakinumayuusukenoMacBook-Air" = inputs.nix-darwin.lib.darwinSystem {
        system = "aaarch64-darwin";
        modules = [
          ./darwin-configuration.nix
          inputs.home-manager.darwinModules.home-manager
        ];
      };
    };
<<<<<<< HEAD
=======
    homeConfigurations = {
      myHome = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = import inputs.nixpkgs {
          system = "x86_64-linux";
          #system = "aarch64-darwin";
          config.allowUnfree = true;
        };
        extraSpecialArgs = {
          inherit inputs;
        };
        modules = [ ./home-manager/home-nixos.nix ];
      };
    };
    darwinConfigurations."kakinumayuusukenoMacBook-Air" = inputs.nix-darwin.lib.darwinSystem {
      system = "aaarch64-darwin";
      modules = [
        ./darwin-configuration.nix
        inputs.home-manager.darwinModules.home-manager
        inputs.nix-homebrew.darwinModules.nix-homebrew
      ];
    };
  };
>>>>>>> 82f945bbc4938953bec7d0b9bb14ebff9025d956
}
