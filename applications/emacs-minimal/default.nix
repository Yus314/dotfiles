{
  config,
  pkgs,
  inputs,
  ...
}:
let
  inherit (inputs) org-babel;
  tangleOrg = org-babel.lib.tangleOrgBabel { languages = [ "emacs-lisp" ]; };
  lexicalBindingCookie = ";;; -*- lexical-binding: t; -*-\n";
  tangleElisp = content: lexicalBindingCookie + tangleOrg content;
  emacsPkgs = import ../emacs/emacs-toolchain.nix {
    inherit inputs;
    system = pkgs.stdenv.hostPlatform.system;
  };
  emacsPkg = import ./emacspkg {
    pkgs = emacsPkgs;
  };

  # Org の数式プレビューと、日本語を含む LuaLaTeX PDF 出力に必要な TeX 環境。
  texliveForOrg = pkgs.texlive.withPackages (tex: [
    tex.scheme-medium
    tex.bxjscls
    tex.capt-of
    tex.luatexja
    tex.type1cm
    tex.wrapfig
  ]);

  # modules/ ディレクトリから .org ファイルを自動列挙
  modulesDir = ./elisp/modules;
  moduleFiles = builtins.attrNames (
    pkgs.lib.filterAttrs (name: type: type == "regular" && pkgs.lib.hasSuffix ".org" name) (
      builtins.readDir modulesDir
    )
  );

  selectionFirstPrelude = ''
    (setq selection-first-enable-frontend ${
      if config.programs.emacs.selectionFirst.enable then "t" else "nil"
    })
  '';

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
          text =
            lexicalBindingCookie
            + (if orgFile == "init-selection-batch.org" then selectionFirstPrelude else "")
            + tangleOrg (builtins.readFile (modulesDir + "/${orgFile}"));
        };
      }
    ) moduleFiles
  );

  selectionBatchPackagesDir = ../emacs/elisp/packages;
  selectionBatchPackageFiles = builtins.filter (
    name:
    pkgs.lib.hasSuffix ".el" name
    && (pkgs.lib.hasPrefix "selection-batch" name || name == "selection-first.el")
  ) (builtins.attrNames (builtins.readDir selectionBatchPackagesDir));
  selectionBatchPackageConfigs = builtins.listToAttrs (
    map (file: {
      name = "emacs/packages/${file}";
      value.source = selectionBatchPackagesDir + "/${file}";
    }) selectionBatchPackageFiles
  );
in
{
  imports = [ ./selection-first-options.nix ];

  programs.emacs = {
    enable = true;
    package = emacsPkg.emacs-unstable;
  };

  xdg.configFile = {
    "emacs/init.el".text = tangleElisp (builtins.readFile ./elisp/init.org);
    "emacs/early-init.el".text = tangleElisp (builtins.readFile ./elisp/early-init.org);
    "emacs/.authinfo.gpg".source = ../emacs/.authinfo.gpg;
  }
  // moduleConfigs
  // selectionBatchPackageConfigs;

  home = {
    packages = with pkgs; [
      texliveForOrg
      lean4
      nil
      nixfmt
    ];
  };
}
