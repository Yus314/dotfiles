{ inputs, specialArgs, ... }:
let
  inherit (specialArgs) username;
in
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = false;
    users.${username} = {
      imports = [
        ../common.nix
      ];
    };
    extraSpecialArgs = {
      inherit inputs;
    };
  };
}
