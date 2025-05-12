{
  pkgs,
  org-babel,
  unstable,
  ...
}:
let
  tangle = org-babel.lib.tangleOrgBabel { languages = [ "emacs-lisp" ]; };
  system = pkgs.stdenv.hostPlatform.system;
  emacs-packages = if system == "x86_64-linux" then pkgs.emacs-unstable-pgtk else pkgs.emacs-unstable;
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

          (unstable.emacsPackages.mu4e)
          (unstable.emacsPackages.slack) # stableのバージョンがかなり古いのでunstableを使う
          (pkgs.texlive.combined.scheme-full)
          (pkgs.zathura)
          (pkgs.imagemagick)
          (pkgs.ghq)
          vterm
          (pkgs.tinymist)
          (unstable.emacsPackages.lsp-bridge)

          (unstable.aider-chat)
          (pkgs.tree-sitter)
          (pkgs.emacs-lsp-booster)
          # mu4eのためのパッケッージ
          (pkgs.xapian)
          (pkgs.gmime)
          (pkgs.adwaita-icon-theme)
          (callPackage ./org-modern-indent.nix {
            inherit (pkgs) fetchFromGitHub;
            inherit (epkgs) melpaBuild compat;
          })
          # (callPackage ./ol-emacs-slack.nix {
          # inherit (pkgs) fetchFromGitHub;
          #  inherit (epkgs) melpaBuild dash s;
          #})
          (callPackage ./gcal.nix {
            inherit (pkgs) fetchFromGitHub;
            inherit (epkgs) melpaBuild;
          })
          (callPackage ./typst-ts-mode.nix {
            inherit (pkgs) fetchgit;
            inherit (epkgs) melpaBuild;
          })
          (callPackage ./typst-preview.nix {
            inherit (pkgs) fetchFromGitHub;
            inherit (epkgs) melpaBuild websocket;
          })
          (callPackage ./nursery.nix {
            inherit (pkgs) fetchFromGitHub;
            inherit (epkgs)
              melpaBuild
              org-roam
              ht
              async
              f
              consult
              org-drill
              pcre2el
              ts
              memoize
              magit
              dash
              ;
          })
          (unstable.emacsPackages.aidermacs)
	  (unstable.emacsPackages.corfu)
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
      (unstable.nixfmt-rfc-style)
      (unstable.rust-analyzer)
      (unstable.basedpyright)
      (unstable.pyright)
      (unstable.ruff)
      (unstable.tinymist)
    ];
  };
}
