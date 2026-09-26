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
    # Local default-profile NEW TUI follows macOS appearance while running.
    # Classic CLI retains startup-only selection; gateway packages are unchanged.
    _module.args.hermesMacosLiveSkin = true;

    imports = [
      ../../../applications/kaggle
      ../../../applications/hermes-agent
      ../../../applications/hermes-session-archive
      ../../../applications/omniwm
      ../../../applications/ssh
    ];
    # Goku remains enabled by the shared Darwin profile for other hosts;
    # watari uses Kanata and must not generate a competing Karabiner mapping.
    programs.goku.enable = lib.mkForce false;
    programs.man.enable = false;

    # These application bundles are self-updated on watari. Keep the existing
    # writable copies instead of reconciling them with copyApps' --delete.
    targets.darwin.copyApps.enable = false;

    # Keep the browser package, profile registration, preferences and extension
    # packages declarative, but leave browser-owned mutable state in place.
    programs.zen-browser.profiles.kaki = {
      settings."extensions.webextensions.ExtensionStorageIDB.enabled" = false;
      extensions = {
        force = lib.mkForce false;
        settings = lib.mkForce { };
      };
      search = {
        force = lib.mkForce false;
        default = lib.mkForce null;
        engines = lib.mkForce { };
      };
      spaces = lib.mkForce { };
      keyboardShortcuts = lib.mkForce [ ];
    };

    # The current HomeManager font tree is locally owned on watari. Retain the
    # version marker, but do not run the module's rsync --delete reconciliation.
    home.file."Library/Fonts/.home-manager-fonts-version".onChange = lib.mkForce "";

    home.sessionPath = [ "$HOME/.local/bin" ];
  };

  # OmniWM refuses to start while yabai is resident. Keep the old window
  # manager disabled; the host-specific skhd config only fills OmniWM's
  # application-launch and close-window gaps.
  services.yabai.enable = lib.mkForce false;
}
