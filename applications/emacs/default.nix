{
  pkgs,
  inputs,
  ...
}:
let
  inherit (inputs) org-babel;
  tangle = org-babel.lib.tangleOrgBabel { languages = [ "emacs-lisp" ]; };
  sources = pkgs.callPackage ../../sources/generated.nix { };
  emacsPkg = import ./emacspkg {
    inherit pkgs sources;
  };
in
{
  programs.emacs = {
    enable = true;
    package = emacsPkg.emacs-unstable;
  };
  home = {
    file = {
      ".emacs.d/init.el".text = tangle (builtins.readFile ./elisp/init.org);
      ".emacs.d/early-init.el".text = tangle (builtins.readFile ./elisp/early-init.org);
    };
    packages = with pkgs; [
      nil
      nixfmt-rfc-style
      rust-analyzer
      basedpyright
      pyright
      ruff
      tinymist
      terraform-ls
    ];
  };
}
