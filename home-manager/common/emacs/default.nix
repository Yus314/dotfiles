{
  pkgs,
  org-babel,
  unstable,
  ...
}:
let
  tangle = org-babel.lib.tangleOrgBabel { languages = [ "emacs-lisp" ]; };
  system = pkgs.stdenv.hostPlatform.system;
  emacs-packages = if system == "x86_64-linux" then pkgs.emacs-unstable-pgtk else unstable.emacs30;
in
{
  programs.emacs ={
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
          (pkgs.texlive.combined.scheme-full)
          (pkgs.zathura)
          (pkgs.imagemagick)
          (pkgs.ghq)
          vterm
          (unstable.emacsPackages.lsp-bridge)
          (pkgs.tinymist)

	        (pkgs.tree-sitter)
      (pkgs.emacs-lsp-booster)
      # mu4eのためのパッケッージ
      (pkgs.mu)
      (pkgs.xapian)
      (pkgs.gmime)
	  (pkgs.adwaita-icon-theme)
	  
        ];
    };
  };
  home = {
    file = {
      ".emacs.d/init.el".text = tangle (builtins.readFile ./elisp/init.org);
      ".emacs.d/early-init.el".text = tangle (builtins.readFile ./elisp/early-init.org);
    };
    packages = with pkgs; [
      nil
      (unstable.rust-analyzer)
      (unstable.basedpyright)
      (unstable.ruff)
      (unstable.ruff-lsp)
    ];
  };

}
