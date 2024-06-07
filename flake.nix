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
  };
  outputs =
    inputs:
    let
      system = "aarch64-darwin";
      unstablePkgs = import inputs.unstable { inherit system; };
    in
    {
      nixosConfigurations = {
        myNixOS = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./configuration.nix ];
        };
      };
      homeConfigurations = {
        myHome = inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = import inputs.nixpkgs {
            #system = "x86_64-linux";
            system = "aarch64-darwin";
            config.allowUnfree = true;
          };
          extraSpecialArgs = {
            inherit inputs;
            inherit unstablePkgs;
          };
          modules = [ ./home-manager/home.nix ];
        };
      };
      darwinConfigurations."kakinumayuusukenoMacBook-Air" = inputs.nix-darwin.lib.darwinSystem {
        modules = [
          ./darwin-configuration.nix
          inputs.home-manager.darwinModules.home-manager
        ];
      };
    };
}
