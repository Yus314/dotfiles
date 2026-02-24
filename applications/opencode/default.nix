{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
let
  # 既存のMCPサーバー設定を再利用し、OpenCode形式に変換
  mcpServers = import ../mcp {
    inherit inputs pkgs;
    ghTokenPath = config.sops.secrets.gh-token-for-mcp.path;
  };

  # Claude形式 → OpenCode形式への変換関数
  # 必要な属性のみを明示的に構築（不明な属性の混入を防止）
  transformMcpServer = _name: server: {
    type = "local";
    command = [ server.command ] ++ (server.args or [ ]);
    environment = server.env or { };
  };
in
{
  programs.opencode = {
    enable = true;
    settings = {
      model = "moonshot/kimi-k2.5";
      autoupdate = false;

      # MCP サーバー設定（既存設定をOpenCode形式に変換）
      mcp = lib.mapAttrs transformMcpServer mcpServers;
    };
  };
}
