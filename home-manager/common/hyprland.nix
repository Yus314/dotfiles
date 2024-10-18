{
  wayland.windowManager.hyprland = {
    enable = false;
    xwayland.enable = true;
    systemd.variables = [ "--all" ];
    extraConfig = ''
                                                	env = XCURSOR_SIZE,24
                                                	env = LIBVA_DRIVER_NAME,nvidia
                                                	env = XDG_SESSION_TYPE,wayland
                                                	env = GBM_BACKEND,nvidia-drm
                                                	env = __GLX_VENDOR_LIBRARY_NAME,nvidia-drm
                  								monitor = , preffered, auto, 1
            									monitor = HDMI-A-1,1920x1080@60.00000,0x0,1 
            									monitor = DP-1,1920x1080@60.00000,1920x0,1
            									monitor = DP-3,1920x1080@60.00000,3840x0,1	
      										monitor = Unknown-1, disable
                              						exec-once = fcitx5 -d
    '';
    # 				env = WLR_DRM_DEVICES,/dev/dri/card0
    #exec-once = waybar
    # monitor=HDMI-A-1,1920x1080@74.97300,-1920x0,1 
    # monitor=DVI-D-1,1920x1080@60.00000,0x0,1 
    # exec-once = [workspace 2]vivaldi --disable-gpu
    # exec-once = [workspace 1]wezterm
    settings = {
      general = {
        "gaps_in" = 5;
        "gaps_out" = 20;
        "border_size" = 2;
      };
      input = {
        "kb_layout" = "us";
        # "kb_variant" = "dvorak";
        "follow_mouse" = 1;
        "force_no_accel" = 0;
      };

      "$mainMod" = "ALT";
      "$terminal" = "kitty";
      bind = [
        "$mainMod, RETURN, exec, $terminal"
        "$mainMod, W, exec, wezterm"
        "$mainMod, Z, exec, vivaldi --disable-gpu"
        "$mainMod, E, exec, emacs"
        "$mainMod, L, exec, slack"
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
        "$mainMod, 1, workspace, 1"
        "$mainMod, 2, workspace, 2"
        "$mainMod, 3, workspace, 3"
        "$mainMod, 4, workspace, 4"
        "$mainMod, 5, workspace, 5"
        "$mainMod, 6, workspace, 6"
        "$mainMod, 7, workspace, 7"
        "$mainMod, 8, workspace, 8"
        "$mainMod, 9, workspace, 9"
      ];
    };
  };
}
