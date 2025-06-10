let
  modifier = "Mod1";
  left = "d";
  down = "h";
  up = "t";
  right = "n";
in
{
  wayland.windowManager.sway = {
    enable = false;
    config = {
      modifier = "Mod1";
      # Use kitty as default terminal
      terminal = "wezterm";
      startup = [ { command = "wezterm"; } ];
      keybindings = {
        "${modifier}+${left}" = "focus left";
        "${modifier}+${down}" = "focus down";
        "${modifier}+${up}" = "focus up";
        "${modifier}+${right}" = "focus right";
        "${modifier}+Shift+${left}" = "move left";
        "${modifier}+Shift+${down}" = "move down";
        "${modifier}+Shift+${up}" = "move up";
        "${modifier}+Shift+${right}" = "move right";
        "${modifier}+v" = "exec vivaldi";
      };
    };
    #wrapperFeatures.gtk = true;
  };
}
