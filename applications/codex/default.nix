{
  config,
  lib,
  pkgs,
  ...
}:

let
  # 音声設定（dunstと統一）
  soundPath = "${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo";

  # 通知スクリプト
  notifyScript = pkgs.writeShellScript "codex-notify" ''
    # JSONペイロードを引数から取得
    INPUT="$1"
    TYPE=$(echo "$INPUT" | ${pkgs.jq}/bin/jq -r '.type // "unknown"')
    MSG=$(echo "$INPUT" | ${pkgs.jq}/bin/jq -r '.["last-assistant-message"] // ""' | head -c 200)

    # 通知を送信
    ${pkgs.dunst}/bin/dunstify \
      -a "codex" \
      -u normal \
      -i "dialog-information" \
      "Codex: タスク完了" \
      "$MSG"

    # 完了音を再生
    ${pkgs.pipewire}/bin/pw-play "${soundPath}/complete.oga" --volume=0.8
  '';
in
{
  # sops.nix設定 - OpenAI API KEY
  sops.secrets = {
    "codex-openai-api-key" = {
      sopsFile = ./secrets.yaml;
      path = "${config.xdg.configHome}/codex/openai_api_key";
      key = "openai_api_key";
      mode = "0600";
    };
  };

  programs.codex = {
    enable = true;
    settings = {
      sandbox_mode = "workspace-write";
      approval_policy = "on-request";
      sandbox_workspace_write = {
        network_access = true;
      };
      # 外部通知コマンド（音声付き、フォーカス状態問わず発火）
      notify = [ "${notifyScript}" ];
      tui = {
        # approval-requested用にtui通知も維持
        notifications = [ "approval-requested" ];
        notification_method = "osc9";
      };
    };
  };

  # Fish shellでOPENAI_API_KEY環境変数を設定
  programs.fish.interactiveShellInit = lib.mkAfter ''
    # Load OpenAI API key for Codex CLI
    if test -f "${config.xdg.configHome}/codex/openai_api_key"
      set -gx OPENAI_API_KEY (cat "${config.xdg.configHome}/codex/openai_api_key")
    end
  '';
}
