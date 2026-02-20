{
  config,
  pkgs,
  lib,
  ...
}:

let
  calendarOrgFile = "${config.home.homeDirectory}/dropbox/calendar.org";
  calendarBaseDir = "${config.home.homeDirectory}/.local/share/calendars/google";

  # khalorg list で使用するカレンダー名
  calendars = [
    "shizhaoyoujie@gmail.com"
    "共有カレンダー"
  ];

  # systemd.path で監視するディレクトリ名（実際のディレクトリ名）
  watchDirs = {
    personal = "shizhaoyoujie@gmail.com";
    shared = "3512a1f6cb8f64e6d897c8e882de5910cef1a834fe96c1634963a76bd50e72dc@group.calendar.google.com";
    # 日本の祝日は変更されないため監視不要
  };

  # sedフィルタ: :END:の次行の不正タイムスタンプを除去
  sedFilter = "sed '/^:END:$/ { n; /^[[:space:]]*<[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}.*>$/d; }'";

  # org更新専用スクリプト（systemd.path からトリガーされる）
  calsyncOrgScript = pkgs.writeShellScriptBin "calsync-org" ''
    set -euo pipefail

    CALENDAR_ORG="${calendarOrgFile}"
    LOCK_FILE="/tmp/calsync-org.lock"

    # ロック取得（同時実行防止）
    exec 200>"$LOCK_FILE"
    ${pkgs.flock}/bin/flock -n 200 || {
      echo "Another instance is running, skipping..."
      exit 0
    }

    # 最終更新から5秒以内ならスキップ（デバウンス）
    if [ -f "$CALENDAR_ORG" ]; then
      LAST_MOD=$(stat -c %Y "$CALENDAR_ORG" 2>/dev/null || echo 0)
      NOW=$(date +%s)
      if [ $((NOW - LAST_MOD)) -lt 5 ]; then
        echo "Recently updated, skipping..."
        exit 0
      fi
    fi

    echo "Exporting calendars to org format..."

    {
      echo "#+TITLE: Google Calendar"
      echo "#+CATEGORY: calendar"
      echo "#+FILETAGS: :calendar:"
      echo ""
      ${lib.concatMapStringsSep "\n      " (cal: ''
        ${lib.getExe pkgs.khalorg} list "${cal}" today 30d 2>/dev/null \
          | ${sedFilter} || true'') calendars}
    } > "$CALENDAR_ORG.tmp"

    # 内容が変わった場合のみ更新（Emacsのauto-revert対策）
    if ! cmp -s "$CALENDAR_ORG" "$CALENDAR_ORG.tmp" 2>/dev/null; then
      mv "$CALENDAR_ORG.tmp" "$CALENDAR_ORG"
      echo "Calendar updated: $CALENDAR_ORG"
    else
      rm -f "$CALENDAR_ORG.tmp"
      echo "No changes detected"
    fi
  '';

  # 手動実行用スクリプト（vdirsyncer sync + org更新）
  calsyncScript = pkgs.writeShellScriptBin "calsync" ''
    set -euo pipefail

    echo "Synchronizing calendar with vdirsyncer..."
    ${lib.getExe pkgs.vdirsyncer} sync

    echo "Exporting to org format with khalorg..."
    ${lib.getExe calsyncOrgScript}
  '';

in
{
  home.packages = [
    pkgs.khalorg
    calsyncScript
    calsyncOrgScript
  ];

  # systemd.path: 個人カレンダーディレクトリを監視
  systemd.user.paths.calsync-org-personal = {
    Unit = {
      Description = "Watch personal calendar directory for changes";
    };
    Path = {
      PathChanged = "${calendarBaseDir}/${watchDirs.personal}";
      Unit = "calsync-org.service";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # systemd.path: 共有カレンダーディレクトリを監視
  systemd.user.paths.calsync-org-shared = {
    Unit = {
      Description = "Watch shared calendar directory for changes";
    };
    Path = {
      PathChanged = "${calendarBaseDir}/${watchDirs.shared}";
      Unit = "calsync-org.service";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # systemd.service: org更新サービス
  systemd.user.services.calsync-org = {
    Unit = {
      Description = "Export khal calendars to org format";
      # レート制限: 30秒間に最大3回まで
      StartLimitIntervalSec = 30;
      StartLimitBurst = 3;
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${lib.getExe calsyncOrgScript}";
    };
  };

  # フォーマット設定
  xdg.configFile."khalorg/khalorg_format.txt".text = ''
    * {title}
    {timestamps}
    :PROPERTIES:
    :CALENDAR: {calendar}
    :LOCATION: {location}
    :ID: {uid}
    :END:
    {description}
  '';
}
