{ pkgs, ... }:
let mod = "MOD1";
in {

  xsession.windowManager.i3 = {
    enable = true;
    config = {
      keybindings = {
        "${mod}+h" = "focus left";
        "${mod}+l" = "focus right";
        "${mod}+k" = "focus up";
        "${mod}+j" = "focus down";
        "${mod}+Shift+h" = "move left";
        "${mod}+Shift+l" = "move right";
        "${mod}+Shift+k" = "move up";
        "${mod}+Shift+j" = "move down";
        "${mod}+f" = "fullscreen";
        "${mod}+Return" = "exec alacritty";
        "${mod}+Shift+q" = "kill";
        "${mod}+t" = "exec thunar";
        "${mod}+v" = "exec vivaldi";
        "${mod}+s" = "exec gscreenshot -c -s";
      };
    };
  };
}
