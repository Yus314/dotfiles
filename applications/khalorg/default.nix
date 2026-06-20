{
  config,
  pkgs,
  lib,
  ...
}:

let
  calendarOrgFile = "${config.home.homeDirectory}/org/calendar.org";
  calendarBaseDir = "${config.home.homeDirectory}/.local/share/calendars/google";

  # khalorg list で使用するカレンダー名
  calendars = [
    "shizhaoyoujie@gmail.com"
    "共有カレンダー"
    "日本の祝日"
  ];

  # systemd.path で監視するディレクトリ名（実際のディレクトリ名）
  watchDirs = {
    personal = "shizhaoyoujie@gmail.com";
    shared = "3512a1f6cb8f64e6d897c8e882de5910cef1a834fe96c1634963a76bd50e72dc@group.calendar.google.com";
    # 日本の祝日は変更されないため監視不要
  };

  # org-lint/Orgzly互換化フィルタ:
  # khalorg 0.1.2 はユーザー定義テンプレートでも timestamp を見出し直下へ出力するため、
  # PROPERTIES drawer を見出し直下へ移動する。
  normalizeOrgProperties = pkgs.writeShellScript "normalize-khalorg-properties" ''
    ${lib.getExe pkgs.perl} -0pi -e '
      s/(^\* [^\n]*\n)([^\n]*<[0-9]{4}-[0-9]{2}-[0-9]{2}[^\n]*>[^\n]*\n)(:PROPERTIES:\n(?:(?!:END:\n).)*:END:\n)/$1$3$2/gms;
      s/^:LOCATION:[[:space:]]*\n//gm;
    ' "$@"
  '';

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

    TMP_FILE="$CALENDAR_ORG.tmp"
    LOG_FILE="$CALENDAR_ORG.tmp.log"
    : > "$LOG_FILE"

    {
      echo "#+TITLE: Google Calendar"
      echo "#+CATEGORY: calendar"
      echo "#+FILETAGS: :calendar:"
      echo ""
    } > "$TMP_FILE"

    EXPORT_FAILURES=0
    ${lib.concatMapStringsSep "\n    " (cal: ''
      echo "Exporting calendar: ${cal}" >&2
      if ! ${lib.getExe pkgs.khalorg} list ${lib.escapeShellArg cal} today 30d >> "$TMP_FILE" 2>> "$LOG_FILE"; then
        echo "ERROR: khalorg failed for calendar: ${cal}" >&2
        EXPORT_FAILURES=$((EXPORT_FAILURES + 1))
      fi
    '') calendars}

    if [ -s "$LOG_FILE" ]; then
      echo "khalorg diagnostics:" >&2
      sed -n '1,80p' "$LOG_FILE" >&2
    fi

    if [ "$EXPORT_FAILURES" -ne 0 ]; then
      rm -f "$TMP_FILE" "$LOG_FILE"
      echo "ERROR: $EXPORT_FAILURES calendar export(s) failed; keeping existing $CALENDAR_ORG" >&2
      exit 1
    fi

    ${normalizeOrgProperties} "$TMP_FILE"

    EVENT_COUNT=$(grep -c '^\* ' "$TMP_FILE" || true)
    KHAL_NONEMPTY_COUNT=$(${lib.getExe' pkgs.khal "khal"} list today 30d | sed '/^[[:space:]]*$/d' | wc -l)
    if [ "$EVENT_COUNT" -eq 0 ] && [ "$KHAL_NONEMPTY_COUNT" -gt 0 ]; then
      rm -f "$TMP_FILE" "$LOG_FILE"
      echo "ERROR: khal has $KHAL_NONEMPTY_COUNT non-empty line(s), but khalorg exported 0 org headings; keeping existing $CALENDAR_ORG" >&2
      exit 1
    fi

    # 内容が変わった場合のみ更新（Emacsのauto-revert対策）
    if ! cmp -s "$CALENDAR_ORG" "$TMP_FILE" 2>/dev/null; then
      mv "$TMP_FILE" "$CALENDAR_ORG"
      rm -f "$LOG_FILE"
      echo "Calendar updated: $CALENDAR_ORG ($EVENT_COUNT events)"
    else
      rm -f "$TMP_FILE" "$LOG_FILE"
      echo "No changes detected ($EVENT_COUNT events)"
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
  # khalorg 0.1.2 では timestamp の出力位置が固定されるため、最終的なOrgzly互換化は
  # normalizeOrgProperties で行う。
  xdg.configFile."khalorg/khalorg_format.txt".text = ''
    * {title}
    :PROPERTIES:
    :CALENDAR: {calendar}
    :LOCATION: {location}
    :ID: {uid}
    :END:
    {timestamps}
    {description}
  '';
}
