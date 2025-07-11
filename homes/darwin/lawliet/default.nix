{
  pkgs,
  inputs,
  specialArgs,
  ...
}:
let
  inherit (specialArgs) username;
in
{
  imports = [
    ../common.nix
    ../desktop.nix
  ];
  home-manager.users.${username} = {
    imports = [ ../../../applications/ssh ];
    programs.man.enable = false;
  };
}
