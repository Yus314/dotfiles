{ pkgs, ... }:
{
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = [ pkgs.vim ];

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
  nix.package = pkgs.nix;
  nixpkgs.hostPlatform = "aarch64-darwin";
  security.pam.enableSudoTouchIdAuth = true;

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
  home-manager = {
    useGlobalPkgs = true;
    users.kakinumayuusuke = {
      imports = [
        ./home-manager/common
        ./home-manager/macOS
      ];
      home = {
        username = "kakinumayuusuke";
        homeDirectory = "/Users/kakinumayuusuke";
        stateVersion = "24.05";
      };
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
}
