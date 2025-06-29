{ lib, config, ... }:
with lib;
let
  cfg = config.ext.xdg;
in
{
  options.ext.xdg = {
    enable = mkEnableOption "enable additional XDG Base Directory support";
    gpg.enable = mkOption {
      type = types.bool;
      default = true;
    };
  };
  config = mkIf cfg.enable (mkMerge [
    (mkIf cfg.gpg.enable {
      programs.gpg.homedir = "${config.xdg.dataHome}/gnupg";
    })
  ]);
}
