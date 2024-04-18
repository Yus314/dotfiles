{
	description = "A simple NixOS flakes";
	
	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
		nixos-hardware.url = "github:NixOS/nixos-hardware/master";
		home-manager = {
			url = "github:nix-community/home-manager/release-23.11";
			inputs.nixpkgs.follows = "nixpkgs";
		};
		nixvim = {
			url = "github:nix-community/nixvim/nixos-23.11";
			inputs.nixpkgs.follows = "nixpkgs";
		};
		
	};
	outputs = inputs: {
		nixosConfigurations = {
			myNixOS = inputs.nixpkgs.lib.nixosSystem {
				system = "x86_64-linux";
				modules = [
					./configuration.nix
				];
			};
		};
		homeConfigurations = {
			myHome = inputs.home-manager.lib.homeManagerConfiguration {
				pkgs = import inputs.nixpkgs {
					system = "x86_64-linux";
					config.allowUnfree = true;
				};
				extraSpecialArgs = {
					inherit inputs;
					};
				modules = [
					./home.nix
				];
			};
		};
	};

}
