{
  inputs,
  pkgs,
  ghTokenPath ? null,
  ...
}:
# MCP servers configuration using mcp-servers-nix module system
(
  inputs.mcp-servers.lib.evalModule pkgs {
    programs = {
      # Context7 MCP - 最新ドキュメント・コード例提供
      context7 = {
        enable = true;
      };
    };
  }
  // pkgs.lib.optionalAttrs (ghTokenPath != null) {
    github = {
      command = "${pkgs.lib.getExe pkgs.github-mcp-server}";
      env = {
        GITHUB_PERSONAL_ACCESS_TOKEN_FILE = ghTokenPath;
      };
    };
  }
  // {
    adb-mcp = {
      command = "${pkgs.lib.getExe pkgs.adb-mcp}";
    };
  }
).config.settings.servers
