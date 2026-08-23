{
  inputs,
  lib,
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
    # Goku remains enabled by the shared Darwin profile for other hosts;
    # watari uses Kanata and must not generate a competing Karabiner mapping.
    programs.goku.enable = lib.mkForce false;
    programs.man.enable = false;
  };
}
