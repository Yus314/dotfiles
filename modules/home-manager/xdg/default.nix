{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.ext.xdg;
  xdgSessionVariables = {
    ANDROID_AVD_HOME = "${config.xdg.dataHome}/android/avd";
    ANDROID_USER_HOME = "${config.xdg.dataHome}/android";
    CARGO_HOME = "${config.xdg.dataHome}/cargo";
    CUDA_CACHE_PATH = "${config.xdg.cacheHome}/nv";
    DOCKER_CONFIG = "${config.xdg.configHome}/docker";
    ELAN_HOME = "${config.xdg.dataHome}/elan";
    GOPATH = "${config.xdg.dataHome}/go";
    GRADLE_USER_HOME = "${config.xdg.dataHome}/gradle";
    LEIN_HOME = "${config.xdg.dataHome}/lein";
    MAVEN_OPTS = "-Dmaven.repo.local=${config.xdg.cacheHome}/maven/repository";
    NPM_CONFIG_CACHE = "${config.xdg.cacheHome}/npm";
    RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
    WGETRC = "${config.xdg.configHome}/wget/wgetrc";
  };
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
    {
      home.sessionVariables = xdgSessionVariables;
      # Graphical sessions launched by greetd/niri use the systemd user manager
      # before a login shell sources hm-session-vars. Keep both environments in sync.
      systemd.user.sessionVariables = xdgSessionVariables;
      home.packages = [
        (pkgs.writeShellScriptBin "adb" ''
          export HOME=${escapeShellArg config.xdg.dataHome}
          export ANDROID_AVD_HOME=${escapeShellArg "${config.xdg.dataHome}/android/avd"}
          export ANDROID_USER_HOME=${escapeShellArg "${config.xdg.dataHome}/android"}
          exec ${pkgs.android-tools}/bin/adb "$@"
        '')
      ];
      home.sessionPath = [
        "${config.xdg.dataHome}/cargo/bin"
        "${config.xdg.dataHome}/go/bin"
      ];
      home.sessionVariablesExtra = ''
        install -d -m 700 ${config.xdg.stateHome}/wget
      '';
      xdg.configFile."wget/wgetrc" = {
        text = ''
          hsts-file = ${config.xdg.stateHome}/wget/hsts
        '';
        force = true;
      };
      xdg.dataFile."lein/profiles.clj".text = ''
        {:user {:local-repo "${config.xdg.cacheHome}/maven/repository"}}
      '';
      xdg.dataFile.".android".source =
        config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/android";
    }
    (mkIf cfg.gpg.enable {
      programs.gpg.homedir = "${config.xdg.dataHome}/gnupg";
    })
    (mkIf cfg.python.enable {
      home.sessionVariables = {
        PYTHONSTARTUP = "${config.xdg.configHome}/python/pythonstartup";
        JUPYTER_PLATFORM_DIRS = 1;
      };
      home.sessionVariablesExtra = ''
        install -d -m 700 ${config.xdg.cacheHome}/python
        if [ -e ${config.xdg.cacheHome}/python/history ]; then
          chmod 600 ${config.xdg.cacheHome}/python/history
        else
          install -m 600 /dev/null ${config.xdg.cacheHome}/python/history
        fi
      '';
      xdg.configFile."python/pythonstartup".source = ./pythonstartup;
    })
    (mkIf cfg.zsh.enable {
      programs.zsh = {
        dotDir = "${config.xdg.configHome}/zsh";
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
