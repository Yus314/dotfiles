{
  pkgs,
  org-babel,
  unstable,
  ...
}:
let
  tangle = org-babel.lib.tangleOrgBabel { languages = [ "emacs-lisp" ]; };
  system = pkgs.stdenv.hostPlatform.system;
  emacs-packages = if system == "x86_64-linux" then pkgs.emacs-pgtk else unstable.emacs30;
in
{
  programs.emacs = {
    enable = true;
    package = pkgs.emacsWithPackagesFromUsePackage {
      config = ./elisp/init.org;
      defaultInitFile = true;
      package = emacs-packages;
      alwaysTangle = true;
      override = final: prev: {
        withXwidgets = true;
        withNativeComplation = false;
      };
      extraEmacsPackages =
        epkgs: with epkgs; [
          (treesit-grammars.with-grammars (
            p: with p; [
              tree-sitter-elisp
              tree-sitter-nix
              tree-sitter-yaml
              tree-sitter-rust
              tree-sitter-python
              tree-sitter-typst
            ]
          ))
          mu4e
          (unstable.emacsPackages.slack) # stableのバージョンがかなり古いのでunstableを使う
          (unstable.emacsPackages.lsp-bridge)
          (pkgs.texlive.combined.scheme-full)
          (pkgs.zathura)
          (pkgs.nil)
          (pkgs.imagemagick)
          (pkgs.ghq)
          vterm
          (unstable.basedpyright)
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
      # mu4eのためのパッケッージ
      mu
      xapian
      gmime
      (unstable.adwaita-icon-theme)
      (unstable.tinymist) # typstのlsp
    ];
  };

}
