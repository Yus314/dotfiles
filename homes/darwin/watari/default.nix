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
    ./skhd.nix
    ./syncthing.nix
  ];
  home-manager.users.${username} = {
    imports = [
      ../../../applications/hermes-agent
      ../../../applications/hermes-session-archive
      ../../../applications/omniwm
      ../../../applications/ssh
    ];
    # Goku remains enabled by the shared Darwin profile for other hosts;
    # watari uses Kanata and must not generate a competing Karabiner mapping.
    programs.goku.enable = lib.mkForce false;
    programs.man.enable = false;
    home.sessionPath = [ "$HOME/.local/bin" ];
  };

  # OmniWM refuses to start while yabai is resident. Keep the old window
  # manager disabled; the host-specific skhd config only fills OmniWM's
  # application-launch and close-window gaps.
  services.yabai.enable = lib.mkForce false;
}
