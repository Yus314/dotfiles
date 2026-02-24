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
      sopsFile = ../kimi-cli/secrets.yaml;
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
        "kimi-for-coding" = {
          name = "Kimi For Coding";
          npm = "@ai-sdk/anthropic";
          options = {
            baseURL = "https://api.kimi.com/coding/v1";
            apiKey = "{file:${config.xdg.configHome}/opencode/moonshot-api-key}";
          };
          models = {
            k2p5 = {
              name = "Kimi K2.5";
              reasoning = true;
              attachment = false;
              limit = {
                context = 262144;
                output = 32768;
              };
              modalities = {
                input = [
                  "text"
                  "image"
                  "video"
                ];
                output = [ "text" ];
              };
              options = {
                interleaved = {
                  field = "reasoning_content";
                };
              };
            };
          };
        };
      };

      autoupdate = false;
      mcp = lib.mapAttrs transformMcpServer mcpServers;
    };
  };
}
