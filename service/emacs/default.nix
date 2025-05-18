{pkgs, ...}:
let
  emacsPkg = import ../../home-manager/packages/emacs {inherit pkgs;} ; 
  in
{
  services.emacs = {
    enable = pkgs.stdenv.isLinux;
    package = emacsPkg.emacs-unstable;
    defaultEditor = true;
    };
}
