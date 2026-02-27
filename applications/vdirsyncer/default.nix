{
  config,
  pkgs,
  lib,
  ...
}:

{
  # accounts.calendar でカレンダーアカウントを宣言的に定義
  accounts.calendar = {
    basePath = ".local/share/calendars";

    accounts.google = {
      primary = true;
      primaryCollection = "shizhaoyoujie@gmail.com";

      remote = {
        type = "google_calendar";
      };

      local = {
        type = "filesystem";
        fileExt = ".ics";
      };

      vdirsyncer = {
        enable = true;
        collections = [
          "from a"
          "from b"
        ];
        conflictResolution = "remote wins";
        clientIdCommand = [
          "cat"
          "${config.xdg.configHome}/vdirsyncer/client_id"
        ];
        clientSecretCommand = [
          "cat"
          "${config.xdg.configHome}/vdirsyncer/client_secret"
        ];
        tokenFile = "${config.xdg.dataHome}/vdirsyncer/google_token";
        metadata = [
          "color"
          "displayname"
        ];
      };

      # khal = {
      #   enable = true;
      #   type = "discover";
      #   color = "auto";
      # };
    };
  };

  # programs.vdirsyncer で設定ファイルを自動生成
  programs.vdirsyncer.enable = true;

  # services.vdirsyncer でsystemdタイマーを自動設定（Linux only）
  services.vdirsyncer = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    frequency = "*:0/15";
  };

  # SOPS設定
  sops.secrets = {
    "vdirsyncer-client-id" = {
      sopsFile = ./secrets.yaml;
      path = "${config.xdg.configHome}/vdirsyncer/client_id";
      key = "google_client_id";
    };
    "vdirsyncer-client-secret" = {
      sopsFile = ./secrets.yaml;
      path = "${config.xdg.configHome}/vdirsyncer/client_secret";
      key = "google_client_secret";
    };
  };
}
