{ pkgs, ... }:
{
  programs.ssh = {
    enable = true;
    matchBlocks = {
      "127.0.0.53" = {
        user = "kaki";
        port = 53;
        proxyCommand = "${pkgs.lib.getExe pkgs.cloudflared} access ssh --hostname test.mdip2home.com";
        #       identityFile = [
        #        "~/.ssh/id_ed25519"
        #     ];
      };
      "rem" = {
        host = "rem";
        address = "sub.mdip2home.com";
        user = "kaki";
        port = 53;
        proxyCommand = "${pkgs.lib.getExe pkgs.cloudflared} access ssh --hostname sub.mdip2home.com";
        #       identityFile = [
        #        "~/.ssh/id_ed25519"
        #     ];
      };
    };
    includes = [ "config.d/*" ];
  };
  programs.fish = {
    interactiveShellInit = ''
      set -x SSH_AUTH_SOCK $(gpgconf --list-dirs agent-ssh-socket)
    '';
  };
}
