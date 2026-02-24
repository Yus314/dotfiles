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

  apiKeyPlaceholder = config.sops.placeholder."kimi-moonshot-api-key";
in
{
  sops.secrets."kimi-moonshot-api-key" = {
    sopsFile = ./secrets.yaml;
    key = "moonshot_api_key";
    mode = "0600";
  };

  sops.templates."kimi-config.toml" = {
    content = ''
      default_model = "kimi-k2-5"
      default_thinking = false
      default_yolo = false

      [providers.kimi]
      type = "kimi"
      base_url = "https://api.moonshot.ai/v1"
      api_key = "${apiKeyPlaceholder}"

      [models.kimi-k2-5]
      provider = "kimi"
      model = "kimi-k2.5"
      max_context_size = 262144
      capabilities = ["thinking", "image_in", "video_in"]

      [models.kimi-k2-thinking-turbo]
      provider = "kimi"
      model = "kimi-k2-thinking-turbo"
      max_context_size = 262144
      capabilities = ["always_thinking"]

      [loop_control]
      max_steps_per_turn = 100
      max_retries_per_step = 3
      reserved_context_size = 50000

      [services.moonshot_search]
      base_url = "https://api.moonshot.ai/v1"
      api_key = "${apiKeyPlaceholder}"

      [services.moonshot_fetch]
      base_url = "https://api.moonshot.ai/v1"
      api_key = "${apiKeyPlaceholder}"

      [mcp.client]
      tool_call_timeout_ms = 60000
    '';
    path = "${config.home.homeDirectory}/.kimi/config.toml";
    mode = "0600";
  };

  programs.kimi-cli = {
    enable = true;
    package = inputs.kimi-cli.packages.${pkgs.system}.default;
    mcpServers = transformedMcpServers;
  };
}
