{
  config,
  pkgs,
  inputs,
  ...
}:
let
  inherit (inputs) xremap;
  cskk = pkgs.callPackage ../../pkgs/cskk { };
  fcitx5-cskk = pkgs.libsForQt5.callPackage ../../pkgs/fcitx5-cskk { inherit cskk; };
  fcitx5-cskk-qt = fcitx5-cskk.override { enableQt = true; };
in
{
  imports = [
    ../../modules/nixos
    ../common.nix
    ./services/xremap
    ./services/dropbox
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
  ];

  sops = {
    defaultSopsFile = ../../secrets/default.yaml;
    #age.keyFile = null;
    age = {
      keyFile = "/home/kaki/.config/sops/age/keys.txt";
    };
    #gnupg = {
    #  home = "/home/kaki/.gnupg";
    #  sshKeyPaths = [ ];
    #};
  };

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.inputMethod = {
    type = "fcitx5";
    enable = true;
    fcitx5.addons = [
      pkgs.fcitx5-skk
      pkgs.fcitx5-mozc
      pkgs.fcitx5-gtk
      fcitx5-cskk
      fcitx5-cskk-qt
    ];
    fcitx5.waylandFrontend = true;
  };

  services.dbus.packages = [ config.i18n.inputMethod.package ];

  environment.variables = {
    QT_IM_MODULE = "fcitx";
  };
}
