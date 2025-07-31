{ pkgs, config, ... }:
let
  # モダンカラーパレット定義（2024年トレンド対応）
  colors = {
    # ベーシック通知 - モダンダークテーマ
    normal = {
      bg = "#1e1e2e"; # 深い紫がかったダーク
      fg = "#cdd6f4"; # 柔らかい白
      frame = "#89b4fa"; # 優雅なブルー
    };
    success = {
      bg = "#1e3a2e"; # 深い緑ベース
      fg = "#a6e3a1"; # 明るい緑
      frame = "#50c878"; # エメラルドグリーン
    };
    critical = {
      bg = "#3e1e28"; # 深い赤ベース
      fg = "#f38ba8"; # 柔らかい赤
      frame = "#f85149"; # 鮮やかな赤
    };
    # Claude Code 専用カラー - グラデーション対応
    claude = {
      completion = {
        bg = "#222222";
        fg = "#ffffff";
        frame = "#50c878"; # エメラルドグリーン
        highlight = "#a6e3a1,#50c878,#2e7d32"; # 緑グラデーション（明→中→暗）
      };
      general = {
        bg = "#222222";
        fg = "#ffffff";
        frame = "#42a5f5"; # 水色
        highlight = "#87ceeb,#42a5f5,#1565c0"; # 水色グラデーション（明→中→暗）
      };
    };
  };

  # 音声設定
  audio = {
    path = "${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo";
    volumes = {
      completion = "0.8";
      general = "0.7";
    };
  };

  # 音声再生スクリプト
  playCompletionSound = pkgs.writeShellScript "play-completion-sound" ''
    exec ${pkgs.pipewire}/bin/pw-play ${audio.path}/complete.oga --volume=${audio.volumes.completion}
  '';

  playGeneralSound = pkgs.writeShellScript "play-general-sound" ''
    exec ${pkgs.pipewire}/bin/pw-play ${audio.path}/complete.oga --volume=${audio.volumes.general}
  '';
in
{
  services.dunst = {
    enable = true;
    configFile = "${config.xdg.configHome}/dunst/dunstrc";

    # systemdユーザーサービスとして有効化
    # waybarと同様の設定パターンを採用

    settings = {
      global = {
        # === レイアウト（showcaseデザイン準拠）===
        width = "(100,600)";
        height = "(0,300)";
        offset = "(30,50)";
        origin = "top-right";

        notification_limit = 10;

        # === テキスト ===
        font = "Bizin Gothic Discord NF 12";
        line_height = 0;
        markup = "full";
        format = "<b>%s</b>\\n%b";
        frame_width = 3;
        separator_height = 6;
        padding = 14;
        horizontal_padding = 8;
        text_icon_padding = 0;
        gap_size = 6;

        # === 角丸設定（2024年モダンデザイン）===
        corner_radius = 10;
        corners = "bottom, top-left";
        progress_bar_corner_radius = 50;
        icon_corner_radius = 6;

        # === 透明度設定 ===
        transparency = 0;

        # === アイコン設定 ===
        enable_recursive_icon_lookup = true;
        icon_theme = " Papirus, Adwaita, Papirus-Dark";
        icon_position = "right";
        max_icon_size = 128;
        min_icon_size = 32;

        # === 動作設定 ===
        timeout = 5;
        sort = true;
        idle_threshold = 120;
        show_age_threshold = 60;
        ellipsize = "middle";
        ignore_newline = false;
        stack_duplicates = true;
        hide_duplicate_count = false;
        show_indicators = true;

        # === マウス操作 ===
        mouse_left_click = "close_current";
        mouse_middle_click = "do_action, close_current";
        mouse_right_click = "close_all";
      };

      # === デフォルト通知スタイル ===
      urgency_low = {
        background = colors.normal.bg;
        foreground = colors.normal.fg;
        frame_color = colors.normal.frame;
        timeout = 3;
      };

      urgency_normal = {
        background = colors.normal.bg;
        foreground = colors.normal.fg;
        frame_color = colors.normal.frame;
        timeout = 5;
      };

      urgency_critical = {
        background = colors.critical.bg;
        foreground = colors.critical.fg;
        frame_color = colors.critical.frame;
        timeout = 0;
      };

      # === Claude Code専用通知（モダンデザイン）===
      zclaude-code-completion = {
        appname = "claude-code";
        summary = "タスク完了";
        script = "${playCompletionSound}";
        background = colors.claude.completion.bg;
        foreground = colors.claude.completion.fg;
        frame_color = colors.claude.completion.frame;
        highlight = colors.claude.completion.highlight;
        timeout = 10;
        default_icon = "emblem-checked";
        icon_position = "right";
      };

      zclaude-code-notification = {
        appname = "claude-code";
        summary = "コマンド実行の確認";
        script = "${playGeneralSound}";
        background = colors.claude.general.bg;
        foreground = colors.claude.general.fg;
        frame_color = colors.claude.general.frame;
        highlight = colors.claude.general.highlight;
        timeout = 7;
        default_icon = "dialog-information";
        icon_position = "right";
      };

    };
  };
}
