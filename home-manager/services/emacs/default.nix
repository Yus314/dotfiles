{ pkgs, ... }:
let
  emacsPkg = import ../../packages/emacs { inherit pkgs; };
in
{
  services.emacs = {
    enable = pkgs.stdenv.isLinux;
    package = emacsPkg.emacs-unstable;
    defaultEditor = true;
    #startWithGraphical = true;
  };
}
