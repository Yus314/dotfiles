{ pkgs, ... }:
let
  xremap = pkgs.callPackage ../../../xremap.nix { };
in
{
  home.packages = with pkgs; [
    onedrive
    nvitop
    xremap
  ];
}
