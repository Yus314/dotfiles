{ pkgs, ... }:
let
  modulesDir = ../elisp/modules;
  moduleFiles = builtins.attrNames (
    pkgs.lib.filterAttrs (name: type: type == "regular" && pkgs.lib.hasSuffix ".org" name) (
      builtins.readDir modulesDir
    )
  );

  # 全orgファイルを結合してuse-package宣言を検出
  allOrgContent = builtins.concatStringsSep "\n" (
    [ (builtins.readFile ../elisp/init.org) ]
    ++ map (f: builtins.readFile (modulesDir + "/${f}")) moduleFiles
  );

  # .org 拡張子のファイルとして書き出し（emacsWithPackagesFromUsePackage が org として解析するため）
  combinedConfig = pkgs.writeText "emacs-config.org" allOrgContent;
in
{
  emacs-unstable = pkgs.emacsWithPackagesFromUsePackage {
    config = combinedConfig;
    defaultInitFile = false;
    package = pkgs.emacs-unstable-pgtk;
    alwaysTangle = true;
    override =
      final: prev:
      prev
      // (pkgs.nurEmacsPackages or { })
      // {
        #        lsp-bridge = (prev.lsp-bridge or pkgs.emacsPackages.lsp-bridge).overrideAttrs (old: {
        #          src = /home/kaki/lsp-bridge;
        #        });
      };
    extraEmacsPackages =
      epkgs:
      with epkgs;
      [
        esup
        exec-path-from-shell
        smooth-scroll
        modus-themes
        darkman
        auto-dark
        perfect-margin
        nerd-icons
        nerd-icons-corfu
        winum
        centaur-tabs
        minions
        moody
        spacious-padding
        meow
        puni
        which-key
        vundo
        dmacro
        multiple-cursors
        phi-search
        vertico
        marginalia
        orderless
        consult
        affe
        corfu
        company
        cape
        ellama
        aidermacs
        claude-code-ide
        # lsp-bridge # temporarily disabled due to rapidfuzz build failure on Python 3.13
        # lsp-mode  # temporarily disabled due to build segfault
        # lsp-ui
        nix-ts-mode
        yaml-mode
        rust-mode
        rustic
        python-mode
        # lsp-pyright  # depends on lsp-mode
        sly
        # lean4-mode  # depends on lsp-mode
        typst-ts-mode
        typst-preview
        terraform-mode
        plantuml-mode
        auctex
        auctex-latexmk
        atomic-chrome
        # lean4-mode  # duplicate, depends on lsp-mode
        org-super-agenda
        org-modern
        org-modern-indent
        gcal
        org-roam
        org-roam-ui
        org-roam-review
        org-nix-shell
        citar
        diff-hl
        magit
        forge
        flycheck
        projectile
        pdf-tools
        mistty
        helpful
        avy
        ace-window
        embark
        embark-consult
        quick-sdcv
        lexic
        gt
        rainbow-delimiters
        reformatter
        apheleia
        envrc
        ledger-mode
        mu4e
        dired-narrow
        nerd-icons-dired
        vterm
        vterm-toggle
        slack
        ol-emacs-slack

        (treesit-grammars.with-grammars (
          p: with p; [
            tree-sitter-elisp
            tree-sitter-nix
            tree-sitter-yaml
            tree-sitter-rust
            tree-sitter-python
            tree-sitter-typst
            tree-sitter-hcl # terraform
          ]
        ))
      ]
      ++ [
        pkgs.texlive.combined.scheme-full
        pkgs.zathura
        pkgs.imagemagick
        pkgs.ghq
        pkgs.aider-chat
        pkgs.tree-sitter
        pkgs.emacs-lsp-booster
        # mu4eのためのパッケッージ
        pkgs.xapian
        pkgs.gmime
        pkgs.adwaita-icon-theme
        pkgs.pinentry-emacs
      ];
  };
}
