{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
let
  mcpServers = import ../mcp {
    inherit inputs pkgs;
    ghTokenPath = config.sops.secrets.gh-token-for-mcp.path;
  };

  transformedMcpServers = lib.mapAttrs (
    _name: server:
    {
      command = server.command;
    }
    // lib.optionalAttrs (server ? args && server.args != [ ]) { inherit (server) args; }
    // lib.optionalAttrs (server ? env && server.env != { }) { inherit (server) env; }
  ) mcpServers;
in
{
  sops.secrets."kimi-moonshot-api-key" = {
    sopsFile = ./secrets.yaml;
    key = "moonshot_api_key";
    mode = "0600";
  };

  programs.kimi-cli = {
    enable = true;
    package = inputs.kimi-cli.packages.${pkgs.system}.default;
    mcpServers = transformedMcpServers;
    settings = {
      default_model = "kimi-k2-5";
      default_thinking = false;
      default_yolo = false;

      providers.kimi = {
        type = "kimi";
        base_url = "https://api.moonshot.ai/v1";
        api_key = ""; # KIMI_API_KEY 環境変数で上書き
      };

      models.kimi-k2-5 = {
        provider = "kimi";
        model = "kimi-k2.5";
        max_context_size = 262144;
        capabilities = [
          "thinking"
          "image_in"
          "video_in"
        ];
      };

      models.kimi-k2-thinking-turbo = {
        provider = "kimi";
        model = "kimi-k2-thinking-turbo";
        max_context_size = 262144;
        capabilities = [ "always_thinking" ];
      };

      loop_control = {
        max_steps_per_turn = 100;
        max_retries_per_step = 3;
        reserved_context_size = 50000;
      };

      mcp.client.tool_call_timeout_ms = 60000;
    };
  };

  programs.fish.interactiveShellInit = lib.mkAfter ''
    # Kimi CLI: API key injection from sops secret
    if test -f "${config.sops.secrets."kimi-moonshot-api-key".path}"
      set -gx KIMI_API_KEY (cat "${config.sops.secrets."kimi-moonshot-api-key".path}")
    end
    set -gx KIMI_CLI_NO_AUTO_UPDATE 1
  '';
}
