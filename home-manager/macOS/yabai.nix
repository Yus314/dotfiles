{ pkgs, ... }:
{
  services.yabai = {
    enable = true;
    package = pkgs.yabai;
    enableScriptingAddition = true;
    config = {
      #external_bar = "all:42:0";
      external_bar = "main:0:0";
      top_padding = 0;
      bottom_padding = 0;
      left_padding = 0;
      right_padding = 0;
      window_gap = 0;
      layout = "bsp";
      window_opacity = "on";
      window_animation_duration = 5.0e-2;
      focus_follows_mouse = "autofocus";
      mouse_follows_focus = "on";
    };
    extraConfig = ''
      yabai -m rule --add app=CopyQ manage=off
      yabai -m rule --add app=Pritunl manage=off

      yabai -m rule --add label=emacs app=Emacs manage=on
    '';
  };
}
