{
  programs.ssh = {
    enable = true; 
    matchBlocks = {
      "127.0.0.53" = {
        user = "kaki";
	port = 53;
        proxyCommand = "/Users/kotsu/.nix-profile/bin/cloudflared access ssh --hostname test.mdip2home.com";
        identityFile = [
          "~/.ssh/id_ed25519"
        ];
      };
    };
  };
}
