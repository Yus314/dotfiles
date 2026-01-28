{
  config,
  pkgs,
  ...
}:

{
  # programs.khal で設定ファイルを自動生成
  # カレンダー設定は accounts.calendar.accounts.*.khal で管理
  programs.khal = {
    enable = true;

    locale = {
      timeformat = "%H:%M";
      dateformat = "%Y-%m-%d";
      longdateformat = "%Y-%m-%d";
      datetimeformat = "%Y-%m-%d %H:%M";
      longdatetimeformat = "%Y-%m-%d %H:%M";
      local_timezone = "Asia/Tokyo";
      default_timezone = "Asia/Tokyo";
      firstweekday = 0;
    };

    settings = {
      default = {
        default_calendar = "google";
        highlight_event_days = true;
      };
    };
  };
}
