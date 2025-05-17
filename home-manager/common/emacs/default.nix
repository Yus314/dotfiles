{
  pkgs,
  org-babel,
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
        epkgs:
let
  packages = pkgs.callPackages ./package.nix {inherit  epkgs pkgs;};
in
  with epkgs; [
    esup
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
    lsp-bridge
    lsp-mode
    lsp-ui
    nix-ts-mode
    yaml-mode
    rust-mode
    python-mode
    lsp-pyright
    typst-ts-mode
    packages.typst-preview
    org-super-agenda
    org-modern
    packages.org-modern-indent
    packages.gcal
    org-roam
    org-roam-ui
    packages.org-roam-review
    citar
    diff-hl
    magit
    flycheck
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
    envrc
    mu4e
    dired-narrow
    nerd-icons-dired
    vterm
    vterm-toggle
    slack
    packages.ol-emacs-slack

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
  ]
      ++
      [
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
