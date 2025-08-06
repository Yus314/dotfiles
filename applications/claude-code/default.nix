{
  my.programs.claude-code = {
    enable = true;
    enableTelemetry = true;
    otelMetricsExporter = "prometheus";
    settings = {
      apiKeyHelper = "";
      includeCoAuthoredBy = false;
      permissions = {
        allow = [ ];
      };
      # Hook設定 - グローバル通知システム
      hooks = {
        # システム通知発生時
        Notification = [
          {
            hooks = [
              {
                type = "command";
                command = "dunstify -a 'claude-code' 'コマンド実行の確認' 'Claudeがコマンドの実行を確認したいようです'";
              }
            ];
          }
        ];
        # Claude応答完了時
        Stop = [
          {
            hooks = [
              {
                type = "command";
                command = "dunstify -a 'claude-code' 'タスク完了' 'Claudeがあなたの依頼を完了させました!'";
              }
            ];
          }
        ];
      };
    };
    userMemory = '''';

    # シンプルにディレクトリ指定のみ
    commandsDirectory = ./commands;
  };

  programs.git.ignores = [
    "**/.claude/settings.local.json"
  ];
}
