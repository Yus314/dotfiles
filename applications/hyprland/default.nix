{
  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;
    systemd.enable = true;
    #systemd.variables = [ "--all" ];
    extraConfig = ''
                                                                 	env = XCURSOR_SIZE,24
                                                                 	env = LIBVA_DRIVER_NAME,nvidia
                                                                 	env = XDG_SESSION_TYPE,wayland
                                                                 	env = GBM_BACKEND,nvidia-drm
                                                                 	env = __GLX_VENDOR_LIBRARY_NAME,nvidia-drm
               monitor=DVI-D-1,1920x1080@60.00000,0x0,1
               monitor=HDMI-A-1,1920x1080@74.97300,1920x0,1
            #   exec-once =  xremap home/kaki/.config/xremap/config.yaml 2>&1 >  home/kaki/shingeta.txt
                     exec-once = waybar
      	       exec-once = fcitx5 -d
    '';

    # 				env = WLR_DRM_DEVICES,/dev/dri/card0
    #
    #                     								monitor = , preffered, auto, 1
    #               									monitor = HDMI-A-1,1920x1080@60.00000,0x0,1
    #               									monitor = DP-1,1920x1080@60.00000,1920x0,1
    #               									monitor = DP-3,1920x1080@60.00000,3840x0,1
    #         										monitor = Unknown-1, disable
    settings = {
      general = {
        "gaps_in" = 5;
        "gaps_out" = 20;
        "border_size" = 2;
      };
      input = {
        "kb_layout" = "us";
        "follow_mouse" = 1;
        "force_no_accel" = 0;
      };

      "$mainMod" = "ALT";
      "$terminal" = "kitty";
      bind = [
        "$mainMod SHIFT Control_R, RETURN, exec, tofi-drun | xargs hyprctl dispatch exec --"
        "$mainMod, Q, exec, qutebrowser"
        "$mainMod, E, exec, emacsclient -nc"
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
      debug = {
        disable_logs = false;
      };
    };
  };
  xdg.configFile = {
    "xremap/config.yaml".source = ../../hhkb.yaml;
  };
}
