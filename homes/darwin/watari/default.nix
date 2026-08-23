{
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
    ./syncthing.nix
  ];
  home-manager.users.${username} = {
    imports = [
      ../../../applications/hermes-agent
      ../../../applications/hermes-session-archive
      ../../../applications/ssh
    ];
    programs.man.enable = false;
  };
}
