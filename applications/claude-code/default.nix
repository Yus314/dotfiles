{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
{
  # sops.nix設定 - gh-token-for-mcp シークレット
  sops.secrets = {
    "gh-token-for-mcp" = {
      sopsFile = ../mcp/secrets.yaml;
    };
  };

  programs.claude-code = {
    enable = true;
    settings = {
      includeCoAuthorBy = false;
      defaultMode = "plan";
      env = {
        CLAUDE_CODE_ENABLE_TELEMETRY = "1";
        OTEL_METRICS_EXPORTER = "prometheus";
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
    agentsDir = ../../applications/claude-code/agents;
    commandsDir = ../../applications/claude-code/commands;
    skills = {
      codex = ./skills/codex;
    };
    mcpServers = import ../../applications/mcp {
      inherit inputs pkgs;
      ghTokenPath = config.sops.secrets.gh-token-for-mcp.path;
    };

    #    };
  };
}
