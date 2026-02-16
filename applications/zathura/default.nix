{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.zathura = {
    enable = true;
  };

  xdg.configFile."zathura/zathurarc.light".text = ''
    set adjust-open "width"
    set recolor "true"
    set recolor-lightcolor "#ffffff"
    set recolor-darkcolor "#000000"
    set recolor-keephue "true"
    set recolor-reverse-video "true"

    map d scroll left
    map s scroll down
    map t scroll up
    map n scroll right

    map ] search forward
    map [ search backward

    map F adjust_window best-fit
    map W adjust_window width

    map P toggle_page_mode
  '';

  xdg.configFile."zathura/zathurarc.dark".text = ''
    set adjust-open "width"
    set recolor "true"
    set recolor-lightcolor "#1e1e1e"
    set recolor-darkcolor "#dcdccc"
    set recolor-keephue "true"
    set recolor-reverse-video "true"

    map d scroll left
    map s scroll down
    map t scroll up
    map n scroll right

    map ] search forward
    map [ search backward

    map F adjust_window best-fit
    map W adjust_window width

    map P toggle_page_mode
  '';

  # checkLinkTargetsの前に既存リンクを削除（Home Manager競合回避）
  home.activation.zathuraCleanup = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    $DRY_RUN_CMD rm -f "${config.xdg.configHome}/zathura/zathurarc"
  '';

  # writeBoundaryの後にリンクを作成
  home.activation.zathuraLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/ln -sf \
      "${config.xdg.configHome}/zathura/zathurarc.light" \
      "${config.xdg.configHome}/zathura/zathurarc"
  '';

  home.packages = with pkgs; [
    zathuraPkgs.zathura_pdf_mupdf
  ];
}
