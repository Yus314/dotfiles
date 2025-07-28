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
    };
    userMemory = '''';

    # シンプルにディレクトリ指定のみ
    commandsDirectory = ./commands;
  };

  programs.git.ignores = [
    "**/.claude/settings.local.json"
  ];
}
