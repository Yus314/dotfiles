{ pkgs, specialArgs, ... }:
let
  inherit (specialArgs) username;
in
{
  imports = [
    ../../applications/shkd
    ../../applications/yabai
  ];
  home-manager.users.${username} = {
    imports = [ ../desktop.nix ];
    home.file."Library/Application\ Support/AquaSKK/keymap.conf".source = ./keymap.conf;
    programs.goku = {
      enable = true;
      configFile = ./karabiner.edn;
    };
  };
}
