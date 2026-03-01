{ pkgs, ... }:
let
  emacsPkg = import ./emacspkg { inherit pkgs; };
in
{
  services.emacs = {
    enable = pkgs.stdenv.isLinux;
    package = emacsPkg.emacs-unstable;
    defaultEditor = false;
    startWithUserSession = "graphical";
  };
}
