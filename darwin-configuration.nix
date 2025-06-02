{
  pkgs,
  emacs-overlay,
  org-babel,
  brew-nix,
  bizin-gothic-discord,
  ...
}:
{
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
   brew-nix.enable = true;
  environment.systemPackages = [
    pkgs.vim
    pkgs.gnupg
    pkgs.pinentry_mac
    pkgs.cloudflared
    #pkgs.brewCasks.dropbox
    #pkgs.brewCasks.aquaskk
    #pkgs.brewCasks.zoom
  ];
  ids.gids.nixbld = 350;

  # Auto upgrade nix package and the daemon service.
  nix.package = pkgs.nix;
  nixpkgs.hostPlatform = "aarch64-darwin";
  security.pam.services.sudo_local.touchIdAuth = true;
nixpkgs.config.allowBroken = true;
nixpkgs.overlays = [
(self: super: {
karabiner-elements = super.karabiner-elements.overrideAttrs (old: {
version = "14.13.0";

    src = super.fetchurl {
      inherit (old.src) url;
      hash = "sha256-gmJwoht/Tfm5qMecmq1N6PSAIfWOqsvuHU8VDJY8bLw=";
    };
				dontFixup = true;
  });
})
];
fonts.packages =
[
bizin-gothic-discord
];

  imports = [
    ./home-manager/macOS/yabai.nix
    ./home-manager/macOS/shkd.nix
  ];

  #fonts.font = with pkgs; [
  #  noto-fonts-cjk-serif
  #  noto-fonts-cjk-sans
  #  noto-fonts-emoji
  #  nerdfonts
  #];
  #home-manager.users.kotsu = import ./home-manager/home.nix;
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
  programs.gnupg = {
    agent = {
      enable = true;
    };
  };
   services.karabiner-elements = {
     enable = true;
     };
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
    extraSpecialArgs = {
      inherit org-babel;
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
  #nix-homebrew = {
   # enable = true;
   # enableRosetta = true;
   # user = "kotsu";
  #};
  system.stateVersion = 5;
}
