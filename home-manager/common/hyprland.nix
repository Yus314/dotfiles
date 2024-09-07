{
  wayland.windowManager.hyprland = {
    enable = true;
    systemd.variables = [ "--all" ];
    extraConfig = ''
                  	env = XCURSOR_SIZE,24
                  	env = LIBVA_DRIVER_NAME,nvidia
                  	env = XDG_SESSION_TYPE,wayland
                  	env = GBM_BACKEND,nvidia-drm
                  	env = __GLX_VENDOR_LIBRARY_NAME,nvidia-drm
                        monitor=,preferred,auto,auto
            			exec-once = vivaldi
      				exec-once = wezterm
    '';
    # 				env = WLR_DRM_DEVICES,/dev/dri/card0
    #exec-once = waybar
    settings = {
      general = {
        "gaps_in" = 5;
        "gaps_out" = 20;
        "border_size" = 2;
      };
      input = {
        "kb_layout" = "us";
        "follow_mouse" = 1;
      };

      "$mainMod" = "ALT";
      "$terminal" = "wezterm";
      bind = [
        "$mainMod, M, exit"
        "$mainMod, RETURN, exec, $terminal"
        "$mainMod, F, exec, vivaldi"
        "$mainMod, N, movefocus, r"
        "$mainMod, D, movefocus, l"
        "$mainMod, H, movefocus, d"
        "$mainMod, T, movefocus, u"
        "$mainMod SHIFT, N, movewindow, r"
        "$mainMod SHIFT, D, movewindow, l"
        "$mainMod SHIFT, H, movewindow, d"
        "$mainMod SHIFT, T, movewindow, u"
        "$mainMod SHIFT, Q, killactive"
      ];
    };
  };
}
