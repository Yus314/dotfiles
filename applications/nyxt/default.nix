{ pkgs, ... }:
{
  programs.nyxt = {
    enable = true;
    config = ./config.lisp;
    extensions = {
      "nx-rbw" = pkgs.nx-rbw;
    };
  };
}
