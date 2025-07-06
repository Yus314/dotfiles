{ pkgs, ... }:
{
  programs.qutebrowser = {
    package = pkgs.qutebrowser;
    enable = true;
    settings = {
      content.blocking.method = "both";
      window.hide_decoration = true;
    };
  };
}
