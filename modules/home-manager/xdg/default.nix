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
    python.enable = mkOption {
      type = types.bool;
      default = true;
    };
    zsh.enable = mkOption {
      type = types.bool;
      default = true;
    };
  };
  config = mkIf cfg.enable (mkMerge [
    (mkIf cfg.gpg.enable {
      programs.gpg.homedir = "${config.xdg.dataHome}/gnupg";
    })
    (mkIf cfg.python.enable {
      home.sessionVariables = {
        PYTHONSTARTUP = "${config.xdg.configHome}/python/pythonstartup";
        JUPYTER_PLATFORM_DIRS = 1;
      };
      home.sessionVariablesExtra = ''
        [ ! -f ${config.xdg.cacheHome}/python/history ] && mkdir -p ${config.xdg.cacheHome}/python && touch ${config.xdg.cacheHome}/python/history
      '';
      xdg.configFile."python/pythonstartup".source = ./pythonstartup;
    })
    (mkIf cfg.zsh.enable {
      programs.zsh = {
        dotDir = ".config/zsh";
        history.path = "${config.xdg.stateHome}/zsh/history";
        envExtra = ''
          	  export SHELL_SESSIONS_DISABLE=1
        '';
        completionInit = ''
          autoload -U compinit
          compinit -d "${config.xdg.cacheHome}/zsh/zcompdump"
        '';

      };
    })
  ]);

}
