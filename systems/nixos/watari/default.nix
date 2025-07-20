# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  inputs,
  config,
  system,
  pkgs,
  ...
}:
let
  inherit (inputs) org-babel emacs-overlay;
in
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./font.nix
    ./nvidia.nix
    ../common.nix
    ./user.nix
  ];
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  services.openssh = {
    enable = true;
  };
  sops = {
    defaultSopsFile = ../../../secrets/default.yaml;
    age = {
      keyFile = "/home/kaki/.config/sops/age/keys.txt";
      generateKey = true;
    };
    #gnupg = {
    #  home = "home/kaki/.gnupg";
    #};

  };
  networking.hostName = "watari";

  services.offlineimap = {
    enable = true;
    path = [ pkgs.mu ];
  };
  services.onedrive.enable = true;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # /boot がいっぱいになったので保存する履歴を制限
  boot.loader.systemd-boot.configurationLimit = 32;

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Asia/Tokyo";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ja_JP.UTF-8";
    LC_IDENTIFICATION = "ja_JP.UTF-8";
    LC_MEASUREMENT = "ja_JP.UTF-8";
    LC_MONETARY = "ja_JP.UTF-8";
    LC_NAME = "ja_JP.UTF-8";
    LC_NUMERIC = "ja_JP.UTF-8";
    LC_PAPER = "ja_JP.UTF-8";
    LC_TELEPHONE = "ja_JP.UTF-8";
    LC_TIME = "ja_JP.UTF-8";
  };

  services.resolved = {
    enable = true;
  };
  hardware.keyboard.qmk.enable = true;
  security.polkit.enable = true;
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    withUWSM = true;
  };
  # for use waybar
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  security.pam.services.swaylock = {
    fprintAuth = false;
  };
  # Configure keymap in X11
  services.xserver.xkb.layout = "us";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    git
    firefox
    mu
    sops
    age
    pinentry-emacs
  ];
  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-emacs;
  };
  services.pcscd.enable = true;
  system.stateVersion = "25.05"; # Did you read the comment?
}
