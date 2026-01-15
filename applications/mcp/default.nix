{
  inputs,
  pkgs,
  ghTokenPath ? null,
  ...
}:
(inputs.mcp-servers.lib.evalModule pkgs {
  programs = {
    git = {
      enable = true;
    };
  };
  settings.servers = {
    github = pkgs.lib.mkIf (ghTokenPath != null) {
      command = "${pkgs.lib.getExe pkgs.github-mcp-server}";
      env = {
        GITHUB_PERSONAL_ACCESS_TOKEN_FILE = ghTokenPath;
      };
    };
    adb-mcp = {
      command = "${pkgs.lib.getExe pkgs.adb-mcp}";
    };
  };
}).config.settings.servers
#in
#{
#  home.file."Library/Application Support/Claude/claude_desktop_config.json" = {
#    enable = stdenv.hostPlatform.isDarwin;
#    source = mcp-config;
#  };
#
#  xdg.configFile."Claude/claude_desktop_config.json" = {
#    enable = stdenv.hostPlatform.isLinux;
#    source = mcp-config;
#  };
