self: super:
let
  require = path: super.callPackage (import path);
in
{
  #cskk = require ./cskk { };
  #fcitx5-cskk = super.libFortQt5.callPackage (import ./fcitx5-cskk) { };
  #fcitx5-cskk-qt = self.fcitx-cskk-override { enableQt = true; };
  adb-mcp = super.callPackage ./adb-mcp { };
  tf-wrapper = super.callPackage ./tf-wrapper { };
  #  nyxt-4 = super.callPackage ./nyxt { };
  khalorg = super.callPackage ./khalorg { };
  #    inherit (lib) mkWindowsAppNoCC copyDesktopIcons makeDesktopIcon;
  #    wine = pkgs.wineWowPackages.base;
  #  };
}
