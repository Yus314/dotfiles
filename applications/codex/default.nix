{
  config,
  inputs,
  pkgs,
  ...
}:
let
  mcpConfigPath = inputs.mcp-servers.lib.mkConfig pkgs {
    flavor = "codex";
    format = "toml-inline";
    fileName = "config.toml";
    programs = {
      fetch.enable = true;
    };
    settings = {
      profiles = {
        network_enabled = {
          sandbox_workspace_write = {
            network_access = true;
          };
        };
      };
      features = {
        web_search_request = true;
      };
    };
  };
in
{
  programs.codex = {
    enable = true;
  };

  xdg.configFile."codex/config.toml".source = mcpConfigPath;
}
