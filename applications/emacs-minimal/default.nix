{
  pkgs,
  inputs,
  ...
}:
let
  inherit (inputs) org-babel;
  tangle = org-babel.lib.tangleOrgBabel { languages = [ "emacs-lisp" ]; };
  emacsPkg = import ./emacspkg {
    inherit pkgs;
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
          text = tangle (builtins.readFile (modulesDir + "/${orgFile}"));
        };
      }
    ) moduleFiles
  );
in
{
  programs.emacs = {
    enable = true;
    package = emacsPkg.emacs-unstable;
  };

  xdg.configFile = {
    "emacs/init.el".text = tangle (builtins.readFile ./elisp/init.org);
    "emacs/early-init.el".text = tangle (builtins.readFile ./elisp/early-init.org);
    "emacs/.authinfo.gpg".source = ../emacs/.authinfo.gpg;
  }
  // moduleConfigs;

  home = {
    packages = with pkgs; [
      nil
      nixfmt
    ];
  };
}
