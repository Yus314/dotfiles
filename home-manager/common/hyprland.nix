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
      							  monitor=HDMI-A-1,1920x1080@74.97300,-1920x0,1 
      							  monitor=DVI-D-1,1920x1080@60.00000,0x0,1 

                        			exec-once = vivaldi
            						exec-once = fcitx5 -d
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
        "$mainMod, L, exec, swaylock -f -c 000000"
        "$mainMod, S, exec, wlogout"
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
