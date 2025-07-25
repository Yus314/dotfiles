{
  inputs,
  config,
  pkgs,
  ...
}:
let
  inherit (pkgs) stdenv;
  inherit (inputs) mcp-servers;
  mcp-config = mcp-servers.lib.mkConfig pkgs {
    programs = {
      github = {
        enable = true;
        envFile = config.sops.secrets.gh-token-for-mcp.path;
      };
      git = {
        enable = true;
      };
    };
  };
in
{
  home.file."Library/Application Support/Claude/claude_desktop_config.json" = {
    enable = stdenv.hostPlatform.isDarwin;
    source = mcp-config;
  };

  xdg.configFile."Claude/claude_desktop_config.json" = {
    enable = stdenv.hostPlatform.isLinux;
    source = mcp-config;
  };

  sops.secrets.gh-token-for-mcp = {
    sopsFile = ./secrets.yaml;
  };
}
