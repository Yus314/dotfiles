{ pkgs, ... }:
let
  mod = "MOD1";
in
{

  xsession.windowManager.i3 = {
    enable = false;
    config = {
      keybindings = {
        "${mod}+d" = "focus left";
        "${mod}+n" = "focus right";
        "${mod}+t" = "focus up";
        "${mod}+h" = "focus down";
        "${mod}+Shift+d" = "move left";
        "${mod}+Shift+n" = "move right";
        "${mod}+Shift+t" = "move up";
        "${mod}+Shift+h" = "move down";
        "${mod}+f" = "fullscreen";
        "${mod}+Return" = "exec wezterm";
        "${mod}+Shift+q" = "kill";
        "${mod}+i" = "exec thunar";
        "${mod}+v" = "exec vivaldi";
        "${mod}+s" = "exec gscreenshot -c -s";
      };
    };
  };
}
