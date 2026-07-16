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
    assert pkgs.lib.assertMsg (
      builtins.readFile ./emacs-config.org == allOrgContent
    ) "emacs-config.org is stale; run applications/emacs/generate-package-config.py";
    ./emacs-config.org;
in
{
  emacs-unstable = pkgs.emacsWithPackagesFromUsePackage {
    config = combinedConfig;
    defaultInitFile = false;
    package = pkgs.emacs-unstable-pgtk;
    alwaysTangle = true;
    extraEmacsPackages =
      epkgs: with epkgs; [
        exec-path-from-shell
        modus-themes
        darkman
        auto-dark
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
