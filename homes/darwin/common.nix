{pkgs,inputs,...}:{
imports = [
            inputs.home-manager.darwinModules.home-manager
];
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
    users.kotsu = {
      imports = [
	../common.nix
      ];
      home = {
        username = "kaki";
        homeDirectory = "/Users/kaki";
        stateVersion = "25.05";
      };
      home.file.".gnupg/gpg-agent.conf".text = ''
        pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
        default-cache-ttl 34560000
        max-cache-ttl 34560000
      '';

      nixpkgs.config.allowUnfree = true;
    };
          extraSpecialArgs = {
      inherit inputs;
    };
  };
  users = {
    users = {
      kaki = {
        shell = pkgs.zsh;
        home = "/Users/kotsu";
      };
    };
  };

}
