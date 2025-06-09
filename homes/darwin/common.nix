{
imports = [
            home-manager.darwinModules.home-manager
    nix-homebrew.darwinModules.nix-homebrew
    brew-nix.darwinModules.default
];
    home-manager = {
    #useGlobalPkgs = true;
    users.kotsu = {
      imports = [
        ./home-manager/common
        ./home-manager/macOS
      ];
      home = {
        username = "kotsu";
        homeDirectory = "/Users/kotsu";
        stateVersion = "25.05";
      };
      home.file.".gnupg/gpg-agent.conf".text = ''
        pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
        default-cache-ttl 34560000
        max-cache-ttl 34560000
      '';

      nixpkgs.config.allowUnfree = true;
      nixpkgs.overlays = [ emacs-overlay.overlays.emacs ];
    };
  };
  users = {
    users = {
      kotsu = {
        shell = pkgs.zsh;
        home = "/Users/kotsu";
      };
    };
  };

}
