{
  config,
  lib,
  pkgs,
  ...
}:
let
  cskkDefaultRuleWithEscapeAbort =
    pkgs.runCommand "cskk-default-rule-with-escape-abort"
      {
        src = pkgs.fetchFromGitHub {
          owner = "naokiri";
          repo = "cskk";
          rev = "v3.2.0";
          hash = "sha256-lhLNtSmD5XiG0U6TLWgN+YA/f7UJ/RyHoe5vq5OopuI=";
        };
      }
      ''
            mkdir -p "$out/default"
            cp "$src/assets/rules/default/rule.toml" "$out/default/rule.toml"

            for section in \
              direct.hiragana \
              direct.katakana \
              direct.hankakukatakana \
              direct.zenkaku \
              direct.ascii
            do
              substituteInPlace "$out/default/rule.toml" \
                --replace-fail "[$section]" "[$section]
        \"Escape\" = [\"Abort\"]"
            done
      '';
in
{
  # Create dictionary_list configuration file
  xdg.dataFile."fcitx5/cskk/dictionary_list".text = ''
    type=file,file=${config.xdg.dataHome}/fcitx5/cskk/user.dict,mode=readwrite,encoding=utf-8,complete=false
    type=file,file=${config.xdg.dataHome}/fcitx5/cskk/dictionary/SKK-JISYO.L,mode=readonly,encoding=euc-jp,complete=false
  '';

  # Override the libcskk default rule so Escape aborts from the Direct state inside
  # dictionary registration (e.g. ▼...【】), matching C-g.
  xdg.dataFile."libcskk/rules/default" = {
    source = "${cskkDefaultRuleWithEscapeAbort}/default";
    force = true;
  };

  # Link system dictionary from Nix store
  xdg.dataFile."fcitx5/cskk/dictionary/SKK-JISYO.L".source =
    "${pkgs.skkDictionaries.l}/share/skk/SKK-JISYO.L";

  # Initialize user dictionary file if it doesn't exist
  home.activation.fcitx5CskkSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -f "${config.xdg.dataHome}/fcitx5/cskk/user.dict" ]; then
      $DRY_RUN_CMD mkdir -p "${config.xdg.dataHome}/fcitx5/cskk"
      $DRY_RUN_CMD touch "${config.xdg.dataHome}/fcitx5/cskk/user.dict"
    fi
  '';
}
