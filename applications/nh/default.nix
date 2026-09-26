{ config, ... }:
{
  programs.nh = {
    enable = true;
    flake = "${config.home.homeDirectory}/ghq/github.com/Yus314/dotfiles";
  };
}
