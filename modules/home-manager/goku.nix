{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.goku;
in
{
  options.programs.goku = {
    enable = mkEnableOption "GokuRakuJoudo";

    package = mkPackageOption pkgs "goku" { };

    configFile = mkOption {
      type = types.path;
      description = "The path to your karabiner.edn configuration file.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."karabiner.edn".source = cfg.configFile;
    
    home.activation.gokuGenerateConfig = hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -p "$HOME/.config/karabiner"
      $DRY_RUN_CMD  ${cfg.package}/bin/goku
    '';
  };
}
