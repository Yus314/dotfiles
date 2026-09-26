{ pkgs, ... }:
{
  programs.ssh = {
    enable = true;
    matchBlocks = {
      "kana-lab" = {
        hostname = "100.99.224.61";
        user = "y";
        port = 22;
      };
      "pixel9-termux" = {
        hostname = "pixel-9.tailbd0b41.ts.net";
        user = "u0_a374";
        port = 8022;
        setEnv = {
          TERM = "xterm-256color";
        };
        sendEnv = [ "TERM" ];
        extraOptions = {
          StrictHostKeyChecking = "accept-new";
        };
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
