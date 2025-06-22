{
  config,
  pkgs,
  inputs,
  ...
}:
let
  inherit (inputs) xremap;
in
{
  imports = [
    ../common.nix
    xremap.nixosModules.default
  ];

  services.xremap = {
    enable = true;
    withWlroots = true;
    yamlConfig = builtins.readFile ./watari/test.yml;
  };

  sops = {
    defaultSopsFile = ../../secrets/default.yaml;
    age = {
      keyFile = "/home/kaki/.config/sops/age/keys.txt";
      generateKey = true;
    };
  };
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
        user = "kaki";
      };
    };
  };
  i18n.inputMethod = {
    type = "fcitx5";
    enable = true;
    fcitx5.addons = [
      pkgs.fcitx5-skk
      pkgs.fcitx5-mozc
      pkgs.fcitx5-gtk
      pkgs.fcitx5-cskk
      pkgs.fcitx5-sckk-qt
    ];
    fcitx5.waylandFrontend = true;
  };

  services.dbus.packages = [ config.i18n.inputMethod.package ];

  environment.variables = {
    QT_IM_MODULE = "fcitx";
  };
}
