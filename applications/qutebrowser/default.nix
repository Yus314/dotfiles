{ pkgs, ... }:
{
  programs.qutebrowser = {
    package = pkgs.qutebrowser;
    enable = true;
  };
  home.file.".qutebrowser/userscripts/qute-bitwarden".source = ./qute-bitwarden.py;
}
