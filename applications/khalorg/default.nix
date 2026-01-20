{
  config,
  pkgs,
  lib,
  ...
}:

let
  calendarOrgFile = "${config.home.homeDirectory}/dropbox/calendar.org";
  primaryCalendar = "shizhaoyoujie@gmail.com";

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
      # 【修正】sed をパイプで繋ぎ、重複したタイムスタンプを除去
      # ロジック: ":END:" という行を見つけたら、次の行(n)を読み込み、
      # その行が "<...>" で始まるタイムスタンプなら削除(d)する。
      ${lib.getExe pkgs.khalorg} list "${primaryCalendar}" today 30d \
        | sed '/^:END:$/ { n; /^<.*>--<.*>$/d; }'
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
