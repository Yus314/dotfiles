{ pkgs, config, ... }:
let
  # カラーパレット定義
  colors = {
    normal = {
      bg = "#37474f";
      fg = "#eceff1";
      frame = "#546e7a";
    };
    success = {
      bg = "#2e7d32";
      fg = "#ffffff";
      frame = "#4caf50";
    };
    critical = {
      bg = "#d32f2f";
      fg = "#ffffff";
      frame = "#f44336";
    };
    claude = {
      completion = {
        bg = "#1b5e20";
        fg = "#e8f5e8";
        frame = "#4caf50";
      };
      general = {
        bg = "#263238";
        fg = "#eceff1";
        frame = "#37474f";
      };
    };
  };

  # 音声設定
  audio = {
    path = "${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo";
    volumes = {
      completion = 0.8;
      general = 0.7;
    };
  };

  # 音声再生スクリプト
  playCompletionSound = pkgs.writeShellScript "play-completion-sound" ''
    exec ${pkgs.pipewire}/bin/pw-play ${audio.path}/complete.oga --volume=${toString audio.volumes.completion}
  '';

  playGeneralSound = pkgs.writeShellScript "play-general-sound" ''
    exec ${pkgs.pipewire}/bin/pw-play ${audio.path}/message-new-instant.oga --volume=${toString audio.volumes.general}
  '';
in
{
  services.dunst = {
    enable = true;

    # systemdユーザーサービスとして有効化
    # waybarと同様の設定パターンを採用

    settings = {
      global = {
        # === レイアウト ===
        width = 300;
        height = 100;
        offset = "30x50";
        origin = "top-right";

        # === スタイル ===
        font = "monospace 10";
        frame_width = 2;
        separator_height = 2;
        padding = 8;
        horizontal_padding = 8;
        text_icon_padding = 0;

        # === アイコン ===
        icon_theme = "Adwaita";
        icon_position = "left";
        max_icon_size = 32;

        # === 動作 ===
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

      # 緊急度別の通知スタイル
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
        timeout = 10;
      };

      urgency_low = {
        background = colors.success.bg;
        foreground = colors.success.fg;
        frame_color = colors.success.frame;
        timeout = 3;
      };

      # Claude Code専用の通知ルール
      "claude-code-completion" = {
        appname = "claude-code";
        summary = "*Completed*";
        script = "${playCompletionSound}";
        background = colors.claude.completion.bg;
        foreground = colors.claude.completion.fg;
        frame_color = colors.claude.completion.frame;
        timeout = 10;
      };

      "claude-code-general" = {
        appname = "claude-code";
        script = "${playGeneralSound}";
        background = colors.claude.general.bg;
        foreground = colors.claude.general.fg;
        frame_color = colors.claude.general.frame;
        timeout = 7;
      };
    };
  };
}
