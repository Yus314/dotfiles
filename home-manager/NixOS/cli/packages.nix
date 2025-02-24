{ pkgs, ... }:
{
  home.packages = with pkgs; [
    onedrive
    nvitop
  ];
}
