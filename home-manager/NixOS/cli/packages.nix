{ pkgs, ... }:
let
  xremap = pkgs.callPackage ../../../pkgs/xremap { };
in
{
  home.packages = with pkgs; [
    onedrive
    nvitop
    xremap
  ];
}
