{
  pkgs,
  lib,
  config,
  ...
}:
let
  spotlightArchiveDir = "${config.xdg.dataHome}/SpotlightArchive";
in
{
  home.packages = [ pkgs.spotlight-downloader ];

  # SpotlightArchive ディレクトリを作成
  home.file.SpotlightArchive = {
    target = "SpotlightArchive/.keep";
    text = "";
  };

  # 毎日実行するsystemd サービス
  systemd.user.services.spotlight-downloader = {
    Unit = {
      Description = "Download Windows Spotlight images";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${lib.getExe pkgs.spotlight-downloader} --out-dir ${spotlightArchiveDir} --locale ja-JP";

      # エラー時のリトライ設定
      Restart = "on-failure";
      RestartSec = "30s";

      # セキュリティ設定
      DynamicUser = false;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = false;
      ReadWritePaths = [ spotlightArchiveDir ];
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
    };
  };

  # 毎日実行するsystemd タイマー
  systemd.user.timers.spotlight-downloader = {
    Unit = {
      Description = "Daily Windows Spotlight image download";
      Requires = [ "spotlight-downloader.service" ];
    };

    Timer = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };

    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
