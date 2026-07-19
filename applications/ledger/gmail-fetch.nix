{
  config,
  pkgs,
  lib,
  ...
}:

let
  ledgerRepo = "${config.home.homeDirectory}/ledger/personal";

  fetchWrapper = pkgs.writeShellApplication {
    name = "ledger-gmail-fetch-wrapper";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      mu
      nix
    ];
    text = ''
      exec "${ledgerRepo}/scripts/ledger-gmail-fetch.sh" "$@"
    '';
  };

  notifyWrapper = pkgs.writeShellApplication {
    name = "ledger-gmail-notify-failure-wrapper";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      libnotify
      curl
      pass
    ];
    text = ''
      exec "${ledgerRepo}/scripts/ledger-gmail-notify-failure.sh" "$@"
    '';
  };
in
{
  systemd.user.services.ledger-gmail = {
    Unit = {
      Description = "Import SMBC card notification mails from local Maildir";
      Documentation = [
        "https://github.com/Yus314/ledger-personal/blob/master/docs/import-workflow.md"
      ];
      After = [ "offlineimap.service" ];
      Wants = [ "offlineimap.service" ];
      OnFailure = [ "ledger-gmail-failure.service" ];
    };
    Service = {
      Type = "oneshot";
      WorkingDirectory = ledgerRepo;
      ExecStart = "${lib.getExe fetchWrapper} --since 2d";
      Nice = 10;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "5min";

      ProtectSystem = "strict";
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictRealtime = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      PrivateTmp = true;
    };
  };

  systemd.user.timers.ledger-gmail = {
    Unit.Description = "Periodic SMBC card notification mail import";
    Timer = {
      OnCalendar = "*-*-* 13,21:30:00";
      RandomizedDelaySec = "30min";
      Persistent = true;
      Unit = "ledger-gmail.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  systemd.user.services.ledger-gmail-failure = {
    Unit = {
      Description = "Notify on ledger-gmail.service failure";
      Documentation = [
        "https://github.com/Yus314/ledger-personal/blob/master/docs/import-workflow.md"
      ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe notifyWrapper;
    };
  };
}
