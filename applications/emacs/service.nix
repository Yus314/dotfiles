{ pkgs, ... }:
let
  sources = pkgs.callPackage ../../sources/generated.nix;
  emacsPkg = import ./emacspkg { inherit pkgs sources; };
in
{
  services.emacs = {
    enable = pkgs.stdenv.isLinux;
    package = emacsPkg.emacs-unstable;
    defaultEditor = true;
    startWithUserSession = "graphical";
  };
}
