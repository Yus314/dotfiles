{ pkgs, ... }:
{
  home.packages = with pkgs; [ skimpdf google-chrome ];
}
