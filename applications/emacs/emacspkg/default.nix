{ pkgs, ... }:
{
  emacs-unstable = pkgs.emacsWithPackagesFromUsePackage {
    config = ../elisp/init.org;
    defaultInitFile = true;
    package = pkgs.emacs-unstable-pgtk;
    alwaysTangle = true;
    override = final: prev: prev // (pkgs.nurEmacsPackages or { });
    extraEmacsPackages =
      epkgs:
      with epkgs;
      [
        esup
        exec-path-from-shell
        smooth-scroll
        modus-themes
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
        #lsp-bridge
        lsp-mode
        lsp-ui
        nix-ts-mode
        yaml-mode
        rust-mode
        rustic
        python-mode
        lsp-pyright
        typst-ts-mode
        typst-preview
        terraform-mode
        org-super-agenda
        org-modern
        org-modern-indent
        gcal
        org-roam
        org-roam-ui
        org-roam-review
        citar
        diff-hl
        magit
        flycheck
        projectile
        pdf-tools
        mistty
        helpful
        avy
        ace-window
        embark
        embark-consult
        go-translate
        rainbow-delimiters
        reformatter
        apheleia
        envrc
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
        pkgs.tinymist

        pkgs.aider-chat
        pkgs.tree-sitter
        pkgs.emacs-lsp-booster
        # mu4eのためのパッケッージ
        pkgs.xapian
        pkgs.gmime
        pkgs.adwaita-icon-theme
      ];
  };
}
