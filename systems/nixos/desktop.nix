{ pkgs, ... }:
{
  i18n = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      addons = [ pkgs.fcitx5-skk ];
      waylandFrontend = true;
    };
  };
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --remember-session --cmd niri-session";
        user = "kaki";
      };
    };
  };
}
