{
  pkgs,
  inputs,
  ...
}:
let
  inherit (inputs) emacs-overlay;
in
{
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  environment.systemPackages = [
    pkgs.vim
    pkgs.pinentry_mac
    pkgs.cloudflared
  ];
  ids.gids.nixbld = 350;
  system.primaryUser = "kaki";

  networking.hostName = "watari";
  networking.knownNetworkServices = [
    "USB 10/100/1000 LAN"
    "Thunderbolt Bridge"
    "Wi-Fi"
  ];

  fonts.packages = [
    pkgs.bizin-gothic-nf
  ];

  imports = [
    ../common.nix
    ../desktop.nix
  ];

  #fonts.font = with pkgs; [
  #  noto-fonts-cjk-serif
  #  noto-fonts-cjk-sans
  #  noto-fonts-emoji
  #  nerdfonts
  #];

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
  my.services.kanata-macos = {
    enable = true;
    deviceName = "Apple Internal Keyboard / Trackpad";
    appPath = "/Users/kaki/Applications/KanataCanary.app";
    # Adopt the ad-hoc-signed app that passed the five-minute real-device
    # canary without touching its TCC-bound code identity.
    adoptAppPath = "/Users/kaki/Applications/KanataCanary.app";
    adoptCDHash = "8c31a4ec989ae59f4317fe7fa0ad78838f433085";
  };
  services.karabiner-elements.enable = false;
  services.tailscale = {
    enable = true;
    overrideLocalDns = true;
  };
}
