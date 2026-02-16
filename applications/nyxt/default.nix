{ pkgs, ... }:
{
  programs.nyxt = {
    package = pkgs.nyxt-4;
    enable = false;
    config = ./config.lisp;
    extensions = {
      "nx-rbw" = pkgs.nx-rbw;
      "nx-zotero" = pkgs.nx-zotero;
    };
  };
}
