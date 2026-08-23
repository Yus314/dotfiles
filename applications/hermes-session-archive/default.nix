{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  hermesCli = inputs.hermes-agent.packages.${pkgs.system}.messaging;
  sessionArchive = pkgs.writeShellApplication {
    name = "hermes-session-archive";
    runtimeInputs = [
      hermesCli
      pkgs.python3
    ];
    text = ''
      exec ${pkgs.python3}/bin/python ${./session_archive.py} "$@"
    '';
  };
  syncCommand = "${sessionArchive}/bin/hermes-session-archive sync --profiles default --sources cli,discord,telegram --max-exports 50";
in
{
  home.packages = [ sessionArchive ];

  home.activation.hermesSessionArchiveDirectories = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p \
      "$HOME/.local/share/hermes-session-archive/lawliet" \
      "$HOME/.local/share/hermes-session-archive/watari" \
      "$HOME/.local/state/hermes-session-archive"
    $DRY_RUN_CMD chmod 700 \
      "$HOME/.local/share/hermes-session-archive" \
      "$HOME/.local/share/hermes-session-archive/lawliet" \
      "$HOME/.local/share/hermes-session-archive/watari" \
      "$HOME/.local/state/hermes-session-archive"
  '';

  systemd.user.services.hermes-session-archive = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "Export redacted Hermes sessions to the cross-node archive";
    Service = {
      Type = "oneshot";
      ExecStart = syncCommand;
    };
  };

  systemd.user.timers.hermes-session-archive = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "Periodically update the cross-node Hermes session archive";
    Timer = {
      OnCalendar = "*-*-* 00/6:00:00";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  launchd.agents.hermes-session-archive = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${sessionArchive}/bin/hermes-session-archive"
        "sync"
        "--profiles"
        "default"
        "--sources"
        "cli,discord,telegram"
        "--max-exports"
        "50"
      ];
      RunAtLoad = true;
      StartInterval = 21600;
      ProcessType = "Background";
      StandardOutPath = "${config.home.homeDirectory}/.local/state/hermes-session-archive/launchd.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/state/hermes-session-archive/launchd-error.log";
    };
  };
}
