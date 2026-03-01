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
    extraEmacsPackages =
      epkgs: with epkgs; [
        exec-path-from-shell
        modus-themes
        darkman
        auto-dark
        nix-ts-mode

        (treesit-grammars.with-grammars (
          p: with p; [
            tree-sitter-nix
          ]
        ))
      ];
  };
}
