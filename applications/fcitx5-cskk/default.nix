{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Create dictionary_list configuration file
  xdg.dataFile."fcitx5/cskk/dictionary_list".text = ''
    type=file,file=${config.xdg.dataHome}/fcitx5/cskk/user.dict,mode=readwrite,encoding=utf-8,complete=false
    type=file,file=${config.xdg.dataHome}/fcitx5/cskk/dictionary/SKK-JISYO.L,mode=readonly,encoding=euc-jp,complete=false
  '';

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
