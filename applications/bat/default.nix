{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.bat = {
    enable = true;
    themes = { };
  };

  xdg.configFile."bat/config.light".text = "--theme=OneHalfLight";
  xdg.configFile."bat/config.dark".text = "--theme=OneHalfDark";

  home.activation.batCleanup = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    $DRY_RUN_CMD rm -f "${config.xdg.configHome}/bat/config"
  '';

  home.activation.batLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/ln -sf \
      "${config.xdg.configHome}/bat/config.light" \
      "${config.xdg.configHome}/bat/config"
  '';
}
