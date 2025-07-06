{ config, pkgs, ... }:
{
  home.packages = with pkgs; [ bashInteractive ];
  programs.bash = {
    enable = true;
    historyFile = "${config.xdg.configHome}/bash/history";
  };
}
