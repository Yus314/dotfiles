{ lib, config, ... }:
with lib;
let
  cfg = config.etc.xdg;
in
{
  options.ext.xdg = {
    enable = mkEnableOption "enable additional XDG Base Directory support";
  };
  config = mkIf cfg.enable (mkMerge [
  ]);
}
