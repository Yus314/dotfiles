{
  my.programs.claude-code = {
    enable = true;
    enableTelemetry = true;
    otelMetricsExporter = "prometheus";
    settings = {
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
                command = "dunstify -a 'claude-code' 'System Alert' 'Claude Code system notification'";
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
                command = "dunstify -a 'claude-code' 'Task Completed' 'Claude has finished processing your request'";
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
