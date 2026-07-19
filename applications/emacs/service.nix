{ config, pkgs, ... }:
{
  services.emacs = {
    enable = pkgs.stdenv.isLinux;
    package = config.programs.emacs.finalPackage;
    defaultEditor = false;
    startWithUserSession = "graphical";
  };
}
