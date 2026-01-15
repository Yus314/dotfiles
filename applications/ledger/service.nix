{
  pkgs,
  lib,
  config,
  ...
}:
{
  systemd.user.services.hledger-web = {
    Unit = {
      Description = "hledger-web personal finance dashboard";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${lib.getExe pkgs.hledger-web} --serve --file=${config.home.homeDirectory}/test.hledger --host=127.0.0.1 --port=5000 --base-url=https://ledger.mdip2home.com";
      Restart = "on-failure";
      RestartSec = "10s";

      # セキュリティ設定
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [ "${config.home.homeDirectory}/test.hledger" ];
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictRealtime = true;
      RestrictNamespaces = true;
      LockPersonality = true;
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
