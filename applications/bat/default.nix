{
  config,
  lib,
  pkgs,
  ...
}:
let
  ghosttySyntaxMap = "--map-syntax=${lib.escapeShellArg "${config.xdg.configHome}/ghostty/config:Ghostty Config"}";
in
{
  programs.bat = {
    enable = true;
    config = lib.mkForce { };
    themes = { };
  };

  xdg.configFile."bat/config.light".text = ''
    --theme=OneHalfLight
    ${ghosttySyntaxMap}
  '';
  xdg.configFile."bat/config.dark".text = ''
    --theme=OneHalfDark
    ${ghosttySyntaxMap}
  '';

  home.activation.batLink = lib.hm.dag.entryAfter [ "batCache" ] ''
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/ln -sf \
      "${config.xdg.configHome}/bat/config.light" \
      "${config.xdg.configHome}/bat/config"
  '';
}
