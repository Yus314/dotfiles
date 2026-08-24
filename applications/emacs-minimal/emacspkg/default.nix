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

  orgVersion = "9.8.7";
  orgElpaArchive = pkgs.fetchurl {
    url = "https://elpa.gnu.org/packages/org-${orgVersion}.tar.lz";
    hash = "sha256-Gl0e+jT/K8EQ1iY6pKhtX+VmaN+vwnCCM39ZTQ6BUew=";
    # GNU ELPA serves .tar.lz files with Content-Encoding: x-lzip. Preserve
    # the archive bytes so the explicit lzip step below can unpack them.
    curlOptsList = [ "--raw" ];
  };
  orgElpaTar = pkgs.runCommand "org-${orgVersion}.tar" { nativeBuildInputs = [ pkgs.lzip ]; } ''
    lzip -dc ${orgElpaArchive} > "$out"
  '';
in
{
  emacs-unstable = pkgs.emacsWithPackagesFromUsePackage {
    config = combinedConfig;
    defaultInitFile = false;
    package = if pkgs.stdenv.isDarwin then pkgs.emacs-unstable else pkgs.emacs-unstable-pgtk;
    alwaysTangle = true;
    override =
      final: prev:
      prev
      // {
        # Keep the qualified package set reproducible after GNU ELPA moves a
        # superseded Org release from .tar to its compressed .tar.lz archive.
        org =
          assert prev.org.version == orgVersion;
          prev.org.overrideAttrs (_: {
            src = orgElpaTar;
          });

        # The generated nixpkgs expression for lean4-mode 1.1.2 currently has
        # stale dependency arguments.  Build the released package with its
        # actual package metadata until nixpkgs catches up.
        lean4-mode = final.melpaBuild {
          pname = "lean4-mode";
          version = "1.1.2";
          src = pkgs.fetchFromGitHub {
            owner = "leanprover-community";
            repo = "lean4-mode";
            rev = "1.1.2";
            hash = "sha256-DLgdxd0m3SmJ9heJ/pe5k8bZCfvWdaKAF0BDYEkwlMQ=";
          };
          files = ''("*.el" "data")'';
          packageRequires = with final; [
            compat
            dash
            lsp-mode
            magit-section
            transient
          ];
        };
      };
    extraEmacsPackages =
      epkgs:
      let
        selectionBatch = epkgs.trivialBuild {
          pname = "selection-batch";
          version = "0.1.0";
          src = ../../emacs/elisp/packages;
          packageRequires = [ epkgs.meow ];
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
        nix-ts-mode
        org-super-agenda
        lsp-mode
        lean4-mode
        transient

        (treesit-grammars.with-grammars (
          p: with p; [
            tree-sitter-nix
          ]
        ))
      ];
  };
}
