{
  pkgs,
  org-babel,
  unstable,
  ...
}:
let
  tangle = org-babel.lib.tangleOrgBabel { languages = [ "emacs-lisp" ]; };
in
{
  programs.emacs = {
    enable = true;
    package = pkgs.emacsWithPackagesFromUsePackage {
      config = ./elisp/init.org;
      defaultInitFile = true;
      # package = pkgs.emacs-pgtk;
      package = unstable.legacyPackages.x86_64-linux.emacs30-pgtk;
      alwaysTangle = true;
      override = final: prev: { withXwidgets = true; };
      extraEmacsPackages =
        epkgs: with epkgs; [
          (treesit-grammars.with-grammars (
            p: with p; [
              tree-sitter-elisp
              tree-sitter-nix
              tree-sitter-yaml
              tree-sitter-rust
              tree-sitter-python
            ]
          ))
          (pkgs.texlive.combined.scheme-full)
          (pkgs.zathura)
        ];
    };
  };
  home = {
    file = {
      ".emacs.d/init.el".text = tangle (builtins.readFile ./elisp/init.org);
      ".emacs.d/early-init.el".text = tangle (builtins.readFile ./elisp/early-init.org);
    };
    packages = with pkgs; [
      tree-sitter
      emacs-lsp-booster
      nil
      nixfmt-rfc-style
      rust-analyzer
      pyright
      ruff
      (unstable.legacyPackages.x86_64-linux.adwaita-icon-theme)
    ];
  };

}
