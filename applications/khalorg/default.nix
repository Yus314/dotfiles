{
  config,
  pkgs,
  lib,
  ...
}:

let
  calendarOrgFile = "${config.home.homeDirectory}/dropbox/calendar.org";
  calendars = [
    "shizhaoyoujie@gmail.com"
    "共有カレンダー"
  ];

  # sedフィルタ: :END:の次行の不正タイムスタンプを除去
  sedFilter = "sed '/^:END:$/ { n; /^[[:space:]]*<[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}.*>$/d; }'";

  calsyncScript = pkgs.writeShellScriptBin "calsync" ''
    set -euo pipefail

    echo "Synchronizing calendar with vdirsyncer..."
    ${lib.getExe pkgs.vdirsyncer} sync

    echo "Exporting to org format with khalorg..."
    CALENDAR_ORG="${calendarOrgFile}"

    if [ -f "$CALENDAR_ORG" ]; then
      cp "$CALENDAR_ORG" "$CALENDAR_ORG.bak"
    fi

    {
      echo "#+TITLE: Google Calendar"
      echo "#+CATEGORY: calendar"
      echo "#+FILETAGS: :calendar:"
      echo ""
      # 各カレンダーからイベントを出力
      # sedフィルタ: :END:の次行の不正タイムスタンプを除去
      ${lib.concatMapStringsSep "\n      " (cal: ''
        ${lib.getExe pkgs.khalorg} list "${cal}" today 30d \
          | ${sedFilter}'') calendars}
    } > "$CALENDAR_ORG"

    echo "Calendar synced to $CALENDAR_ORG"
  '';
in
{
  home.packages = [
    pkgs.khalorg
    calsyncScript
  ];

  # フォーマット設定（前回と同じでOK）
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
