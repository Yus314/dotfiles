{
  nixpkgs,
  system,
  emacs-overlay,
  org-babel,
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
  emacsPkg = emacs.emacs-unstable;
  Services = import ./services {
    inherit pkgs emacsPkg;
  };
  NixGuiPrograms = import ./NixOS/gui {
    inherit pkgs emacsPkg;
  };
  NixCliPrograms = import ./NixOS/cli {
    inherit pkgs emacsPkg;
  };
  CommomPrograms = import ./common {
    inherit pkgs;
    inherit emacsPkg org-babel;
  };
in
{
  imports = Services ++ NixGuiPrograms ++ NixCliPrograms ++ CommomPrograms;
}
