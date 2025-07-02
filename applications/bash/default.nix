{ pkgs, ... }:
{
  programs.bash = {
    enable = true;
    historyFile = "$XDG_CONFIG_HOME/bash/histry";
  };
}
