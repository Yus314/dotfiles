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
}
