# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  system,
  pkgs,
  unstable,
  emacs-overlay,
  org-babel,
  xremap,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./font.nix
    ./nvidia.nix
    ./greetd.nix
    ./user.nix
    #    ./home-manager/common/dropbox.nix
  ];
  sops = {
    defaultSopsFile = ./secrets/default.yaml;
    age = {
      keyFile = "/home/kaki/.config/sops/age/keys.txt";
      generateKey = true;
    };
    secrets = {
      gh-token = { };
      "dropbox/token/access_token" = { };
      "dropbox/token/token_type" = { };
      "dropbox/token/refresh_token" = { };
      "dropbox/token/expiry" = { };
      cachix-agent-token = {
        sopsFile = ./secrets/cachix.yaml;
      };
    };
    templates = {

      "gh-token" = {
        owner = "kaki";
        group = "users";
        mode = "0440";
        content = ''
          	  access-tokens = github.com=${config.sops.placeholder."gh-token"}
          	'';
      };
      "dropbox.conf" = {
        owner = "kaki";
        group = "users";
        mode = "0440";
        content = ''
          [dropbox]
          type = dropbox
          token = {"access_token":"${config.sops.placeholder."dropbox/token/access_token"}","token_type":"${
            config.sops.placeholder."dropbox/token/token_type"
          }","refresh_token":"${config.sops.placeholder."dropbox/token/refresh_token"}","expiry":"${
            config.sops.placeholder."dropbox/token/expiry"
          }"}
        '';
      };
    };

  };
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      substituters = [
        "https://yus314.cachix.org"
      ];
      trusted-public-keys = [
        "yus314.cachix.org-1:VyHussCju8oVuLg52oE5RDOKMvWIInAvJumaJSvzWvk="
      ];
    };
    extraOptions = ''
      !include ${config.sops.templates."gh-token".path}
    '';
  };
  networking.hostName = "toro";
  services.cachix-agent = {
    enable = true;
    name = "toro";
    credentialsFile = config.sops.secrets.cachix-agent-token.path;
  };
  systemd.user.services.dropbox = {
    description = "Dropbox service";
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "notify";
      ExecStartPre = "/run/current-system/sw/bin/mkdir -p %h/dropbox";
      ExecStart = "${pkgs.rclone}/bin/rclone --config=${
        config.sops.templates."dropbox.conf".path
      } --vfs-cache-mode writes --ignore-checksum mount \"dropbox:\" \"dropbox\" --allow-other";
      ExecStop = "/run/wrappers/bin/fusermount -u %h/dropbox/%i";
      Environment = [ "PATH=/run/wrappers/bin/:$PATH" ];
    };
    wantedBy = [ "default.target" ];

  };

  services.offlineimap = {
    enable = true;
    path = [ pkgs.mu ];
  };
  services.onedrive.enable = true;
  boot.kernelModules = [ "uinput" ];
  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="input", TAG+="uaccess"
  '';
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
  #for dropbox
  programs.fuse.userAllowOther = true;

  programs.fish.enable = true;
  users.users.kaki.shell = pkgs.fish;
  services.resolved = {
    enable = true;
  };
  hardware.keyboard.qmk.enable = true;
  home-manager = {
    users.kaki = {
      imports = [
        ./home-manager/common
        ./home-manager/NixOS/gui
        ./home-manager/NixOS/cli
      ];
      home = {
        username = "kaki";
        homeDirectory = "/home/kaki";
        stateVersion = "24.11";
      };
      nixpkgs.config.allowUnfree = true;
      nixpkgs.overlays = [ emacs-overlay.overlays.emacs ];
    };
    backupFileExtension = "hm-backup";
    extraSpecialArgs = {
      inherit unstable;
      inherit xremap;
      inherit org-babel;
    };
  };
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
  ];
  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-emacs;
  };
  services.pcscd.enable = true;
  system.stateVersion = "24.11"; # Did you read the comment?
}
