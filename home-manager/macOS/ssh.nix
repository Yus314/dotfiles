{pkgs,...}:{
  programs.ssh = {
    enable = true; 
    matchBlocks = {
      "127.0.0.53" = {
        user = "kaki";
	port = 53;
        proxyCommand = "/{pkgs.cloudflare} access ssh --hostname test.mdip2home.com";
        identityFile = [
          "~/.ssh/id_ed25519"
        ];
      };
    };
  };
}
