{
  pkgs,
  emacsPkg,
  org-babel,
  ...
}:
let
  tangle = org-babel.lib.tangleOrgBabel { languages = [ "emacs-lisp" ]; };
in
{
  programs.emacs = {
    enable = true;
    package = emacsPkg;
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
    ];
  };
}
