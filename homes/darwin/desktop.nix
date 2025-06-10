{ pkgs, specialArgs, ... }:
let
  inherit (specialArgs) username;
in{
  imports = [
    ../../applications/shkd
    ../../applications/yabai
  ];
    home-manager.users.${username} = {
    imports = [ ../desktop.nix ];
  };
}
