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

  # emacsWithPackagesFromUsePackage reads this during evaluation, so it must
  # be a source path rather than a derivation. The assertion prevents the
  # generated package-discovery input from drifting from the modular config.
  combinedConfig =
    assert pkgs.lib.assertMsg (builtins.readFile ./emacs-config.org == allOrgContent)
      "emacs-minimal/emacspkg/emacs-config.org is stale; run applications/emacs/generate-package-config.py --profile minimal";
    ./emacs-config.org;
in
{
  emacs-unstable = pkgs.emacsWithPackagesFromUsePackage {
    config = combinedConfig;
    defaultInitFile = false;
    package = pkgs.emacs-unstable-pgtk;
    alwaysTangle = true;
    extraEmacsPackages =
      epkgs:
      let
        selectionBatch = epkgs.trivialBuild {
          pname = "selection-batch";
          version = "0.1.0";
          src = ../../emacs/elisp/packages;
          packageRequires = [ epkgs.meow ];
        };
        # The NUR expression currently passes an obsolete argument to
        # lean4-mode, so package the pinned upstream release directly.
        lean4Mode = epkgs.melpaBuild rec {
          pname = "lean4-mode";
          version = "1.1.2";
          src = pkgs.fetchFromGitHub {
            owner = "leanprover-community";
            repo = "lean4-mode";
            rev = version;
            hash = "sha256-DLgdxd0m3SmJ9heJ/pe5k8bZCfvWdaKAF0BDYEkwlMQ=";
          };
          files = ''("*.el" "data")'';
          packageRequires = with epkgs; [
            compat
            dash
            lsp-mode
            magit-section
          ];
        };
      in
      with epkgs;
      [
        selectionBatch
        corfu
        exec-path-from-shell
        meow
        modus-themes
        darkman
        auto-dark
        lean4Mode
        lsp-mode
        nix-ts-mode
        org-super-agenda

        (treesit-grammars.with-grammars (
          p: with p; [
            tree-sitter-nix
          ]
        ))
      ];
  };
}
