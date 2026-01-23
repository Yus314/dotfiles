{
  pkgs,
  ghTokenPath ? null,
  ...
}:
# Direct MCP servers configuration (avoiding mcp-servers.lib.evalModule to prevent infinite recursion)
{
  # Note: git MCP server temporarily removed - needs package identification
  # git = {
  #   command = "${pkgs.lib.getExe pkgs.git-mcp-server}";
  # };
}
// pkgs.lib.optionalAttrs (ghTokenPath != null) {
  github = {
    command = "${pkgs.lib.getExe pkgs.github-mcp-server}";
    env = {
      GITHUB_PERSONAL_ACCESS_TOKEN_FILE = ghTokenPath;
    };
  };
}
# Note: adb-mcp temporarily disabled
# // {
#   adb-mcp = {
#     command = "${pkgs.lib.getExe pkgs.adb-mcp}";
#   };
# }
