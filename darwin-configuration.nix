{
  pkgs,
  emacs-overlay,
  org-babel,
  ...
}:
{
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = [
    pkgs.vim
    pkgs.gnupg
    pkgs.pinentry_mac
  ];
  ids.gids.nixbld = 30000;

  # Auto upgrade nix package and the daemon service.
  nix.package = pkgs.nix;
  nixpkgs.hostPlatform = "aarch64-darwin";
  security.pam.services.sudo_local.touchIdAuth = true;

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
  #home-manager.users.kakinumayuusuke = import ./home-manager/home.nix;
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
  home-manager = {
    #useGlobalPkgs = true;
    users.kakinumayuusuke = {
      imports = [
        ./home-manager/common
        ./home-manager/macOS
      ];
      home = {
        username = "kakinumayuusuke";
        homeDirectory = "/Users/kakinumayuusuke";
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
      kakinumayuusuke = {
        shell = pkgs.zsh;
        home = "/Users/kakinumayuusuke";
      };
    };
  };
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = "kakinumayuusuke";
  };
  system.stateVersion = 5;
}
