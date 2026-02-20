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
    ./font.nix
    ./nvidia.nix
    ../common.nix
    ./user.nix
    ../desktop.nix
    ./root-ssh.nix
    ./syncthing.nix
  ];
  inherit
    (pkgs.callPackage ./disko-config.nix {
      disks = [ "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S78HNL0Y701814D" ];
    })
    disko
    ;
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  # for bluetooth receiver
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.rtl8761b-firmware ];

  fileSystems."/persistent".neededForBoot = true;

  services.openssh = {
    enable = true;
  };
  services.cloudflared = {
    enable = true;
    tunnels = {
      "8660bc67-a68c-4c63-9ed1-77666eeb3936" = {
        credentialsFile = config.sops.secrets.cloudflared-tunnel-cred-lawliet.path;
        default = "http_status:404";
        ingress = {
          "ledger.mdip2home.com" = "http://localhost:5000";
        };
      };
    };
    certificateFile = config.sops.secrets.cloudflared-tunnel-cert.path;
  };
  sops = {
    defaultSopsFile = ../../../secrets/default.yaml;
    age = {
      keyFile = "/home/kaki/.config/sops/age/keys.txt";
      generateKey = true;
    };
    secrets = {
      cloudflared-tunnel-cert = { };
      cloudflared-tunnel-cred-lawliet = { };
    };
  };
  programs.steam = {
    enable = true;
  };

  programs.virt-manager.enable = true;
  users.groups.libvirtd.members = [ "kaki" ];
  virtualisation.libvirtd.enable = true;
  virtualisation.libvirtd.qemu.swtpm.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  virtualisation.waydroid.enable = true;

  virtualisation.docker.enable = true;

  networking.hostName = "lawliet";

  services.offlineimap = {
    enable = true;
    path = [ pkgs.mu ];
  };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # /boot がいっぱいになったので保存する履歴を制限
  boot.loader.systemd-boot.configurationLimit = 32;

  # Enable networking
  networking.networkmanager.enable = true;

  networking = {
    firewall = {
      enable = true;
      extraCommands = ''
        iptables -A nixos-fw -s 192.168.1.0/24 -j ACCEPT
      '';
    };
  };

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
  programs.niri = {
    enable = true;
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
    pinentry-gnome3
    cloudflared
    # アイコンテーマ (dunst通知用)
    adwaita-icon-theme
    papirus-icon-theme
    docker-compose
    android-tools
  ];
  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-gnome3;
  };
  services.pcscd.enable = true;
  system.stateVersion = "25.05"; # Did you read the comment?
}
