{
  nixpkgs,
  system,
  emacs-overlay,
  ...
}:
let
  sources = nixpkgs.callPackage ../sources/generated.nix { };
  Overlay = import ./overlay/overlay.nix { inherit emacs-overlay; };
  pkgs = import nixpkgs {
    inherit system;
    overlays = Overlay;
  };
  emacs = import ./packages/emacs {
    inherit pkgs sources;
  };
  emacsPkg = emacs.emacs-usntable;
  Services = import ./services {
    inherit pkgs emacsPkg;
  };
in
{
  imports = Services;
}
