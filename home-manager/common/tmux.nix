{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    terminal = "screen-256color";
    extraConfig = ''
      set -ga terminal-features ",alacritty:RGB"
    '';
  };
}
