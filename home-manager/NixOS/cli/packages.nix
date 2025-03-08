{ pkgs, xremap, ... }:
{
  home.packages = with pkgs; [
    onedrive
    nvitop
    xremap
  ];
}
