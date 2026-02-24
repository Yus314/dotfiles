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
  # sops.nix設定追加
  sops.secrets = {
    "moonshot-api-key" = {
      sopsFile = ./secrets.yaml;
      path = "${config.xdg.configHome}/opencode/moonshot-api-key";
      key = "moonshot_api_key";
      mode = "0600";
    };
  };

  programs.opencode = {
    enable = true;
    settings = {
      model = "kimi-for-coding/k2p5";

      provider = {
        moonshot = {
          options = {
            apiKey = "{file:${config.xdg.configHome}/opencode/moonshot-api-key}";
            timeout = false;
          };
        };
      };

      autoupdate = false;
      mcp = lib.mapAttrs transformMcpServer mcpServers;
    };
  };
}
