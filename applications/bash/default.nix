{ pkgs, ... }:
{
  home.packages = with pkgs; [ bashInteractive ];
  programs.bash = {
    enable = true;
    historyFile = "$XDG_CONFIG_HOME/bash/history";
  };
}
