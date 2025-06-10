{
  inputs,
  lib,
  self,
  ...
}:
let
  inherit (inputs) emacs-overlay ;
  in
{
  nixpkgs.overlays = [
    emacs-overlay.overlays.default
  ]  ++ lib.attrValues self.overlays;

  nixpkgs.config.allowUnfree = true;
}
