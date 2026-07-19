{ pkgs, ... }:
{
  #  i18n = {
  #    enable = true;
  #    type = "fcitx5";
  #    fcitx5 = {
  #      addons = [ pkgs.fcitx5-skk ];
  #      waylandFrontend = true;
  #    };
  #  };
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-session --cmd niri-session";
        user = "kaki";
      };
    };
  };
  programs.thunar.enable = true;
  services.gvfs.enable = true;
  services.openssh.allowSFTP = true;

  # Let applications such as Kitty follow darkman's color-scheme over the
  # standard Settings portal when running under Niri.
  xdg.portal = {
    extraPortals = [ pkgs.darkman ];
    config.niri."org.freedesktop.impl.portal.Settings" = "darkman";
  };
}
