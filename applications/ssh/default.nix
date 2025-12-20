{ pkgs, ... }:
{
  programs.ssh = {
    enable = true;
    matchBlocks = {
      "ryuk" = {
        hostname = "test.mdip2home.com";
        user = "kaki";
        port = 22;
        proxyCommand = "${pkgs.lib.getExe pkgs.cloudflared} access ssh --hostname test.mdip2home.com";
        #       identityFile = [
        #        "~/.ssh/id_ed25519"
        #     ];
      };
      "rem" = {
        hostname = "sub.mdip2home.com";
        user = "kaki";
        port = 22;
        proxyCommand = "${pkgs.lib.getExe pkgs.cloudflared} access ssh --hostname sub.mdip2home.com";
        #       identityFile = [
        #        "~/.ssh/id_ed25519"
        #     ];
      };
      "*" = {
        serverAliveInterval = 60;
        serverAliveCountMax = 3;
        controlMaster = "auto";
        controlPersist = "180m";
      };
    };
    #   extraConfig = ''
    #     ClientAliveInterval 60
    #     ClientAliveCountMax 3
    #   '';
    enableDefaultConfig = false;
    includes = [ "config.d/*" ];
  };
  programs.fish = {
    interactiveShellInit = ''
      set -x SSH_AUTH_SOCK $(gpgconf --list-dirs agent-ssh-socket)
    '';
  };
}
