{
  pkgs,
  inputs,
  ...
}:
let
  inherit (inputs) org-babel;
  tangleOrg = org-babel.lib.tangleOrgBabel { languages = [ "emacs-lisp" ]; };
  lexicalBindingCookie = ";;; -*- lexical-binding: t; -*-\n";
  tangleElisp = content: lexicalBindingCookie + tangleOrg content;
  emacsPkgs = import ./emacs-toolchain.nix {
    inherit inputs;
    system = pkgs.stdenv.hostPlatform.system;
  };
  sources = emacsPkgs.callPackage ../../sources/generated.nix { };
  emacsPkg = import ./emacspkg {
    pkgs = emacsPkgs;
    inherit sources;
  };

  # modules/ ディレクトリから .org ファイルを自動列挙
  modulesDir = ./elisp/modules;
  moduleFiles = builtins.attrNames (
    pkgs.lib.filterAttrs (name: type: type == "regular" && pkgs.lib.hasSuffix ".org" name) (
      builtins.readDir modulesDir
    )
  );

  # 各モジュールの xdg.configFile エントリを生成
  moduleConfigs = builtins.listToAttrs (
    map (
      orgFile:
      let
        elFile = builtins.replaceStrings [ ".org" ] [ ".el" ] orgFile;
      in
      {
        name = "emacs/modules/${elFile}";
        value = {
          text = tangleElisp (builtins.readFile (modulesDir + "/${orgFile}"));
        };
      }
    ) moduleFiles
  );

  # packages/ ディレクトリからローカル Emacs package を自動列挙
  packagesDir = ./elisp/packages;
  packageFiles = builtins.attrNames (
    pkgs.lib.filterAttrs (name: type: type == "regular" && pkgs.lib.hasSuffix ".el" name) (
      builtins.readDir packagesDir
    )
  );
  packageConfigs = builtins.listToAttrs (
    map (file: {
      name = "emacs/packages/${file}";
      value.source = packagesDir + "/${file}";
    }) packageFiles
  );
in
{
  programs.emacs = {
    enable = true;
    package = emacsPkg.emacs-unstable;
  };

  xdg.configFile = {
    "emacs/init.el".text = tangleElisp (builtins.readFile ./elisp/init.org);
    "emacs/early-init.el".text = tangleElisp (builtins.readFile ./elisp/early-init.org);
    "emacs/.authinfo.gpg".source = ./.authinfo.gpg;
  }
  // moduleConfigs
  // packageConfigs;

  home = {
    packages = with pkgs; [
      nil
      nixfmt
      #rust-analyzer
      basedpyright
      pyright
      ruff
      tinymist
      terraform-ls
      # Common Lisp
      sbcl
    ];
  };
}
