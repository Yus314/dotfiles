#  Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  inputs,
  config,
  pkgs,
  ...
}:
let
in
{
  imports = [
    # Include the results of the hardware scan.
    ./lab-main-hardware-configuration.nix
    ../common.nix
    ../services/dropbox
  ];
  fonts.packages = [ pkgs.bizin-gothic-nf ];
  fonts.fontDir.enable = true;
  programs.gnupg.agent = {
    enable = true;
  };
  sops = {
    secrets = {
      cachix-agent-token = {
        sopsFile = ../../../secrets/cachix.yaml;
      };
      cloudflared-tunnel-cert = {
      };
      cloudflared-tunnel-cred = {
      };
    };
  };

  services.onedrive.enable = true;
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    ensureDatabases = [ "diesel_demo" ];
    authentication = pkgs.lib.mkOverride 10 ''
            #type database  DBuser  auth-method
      	  local  all       all   trust
    '';
  };

  services.cloudflared = {
    enable = true;
    tunnels."d2bb7add-9929-4016-a839-0e03a71bdb14" = {
      credentialsFile = "${config.sops.secrets.cloudflared-tunnel-cred.path}";
      default = "http_status:404";
      ingress = {
        "test.mdip2home.com" = "ssh://localhost:22";
      };
    };
    certificateFile = "${config.sops.secrets.cloudflared-tunnel-cert.path}";
  };
  # Bootloader
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      #    access-tokens = ;
      substituters = [
        "https://yus314.cachix.org"
      ];
      trusted-public-keys = [
        "yus314.cachix.org-1:VyHussCju8oVuLg52oE5RDOKMvWIInAvJumaJSvzWvk="
      ];
    };
  };
  #boot.kernelModules = ["uinput"];
  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="input", TAG+="uaccess"
  '';
  virtualisation.docker = {
    enable = true;
    enableNvidia = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };
  hardware.nvidia-container-toolkit = {
    enable = true;
  };
  virtualisation.docker.daemon.settings.features.cdi = true;
  virtualisation.docker.rootless.daemon.settings.features.cdi = true;
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowBroken = true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.extraModulePackages = with config.boot.kernelPackages; [
    r8125
    nvidia_x11
  ];
  boot.kernelModules = [
    "r8125"
    "uinput"
  ];
  boot.initrd.kernelModules = [ "nvidia" ];
  boot.loader.systemd-boot.configurationLimit = 14;
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    #	datacenter.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
  networking.hostName = "ryuk"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;
  services.resolved = {
    enable = true;
  };

  # Set your time zone.
  time.timeZone = "Asia/Tokyo";

  # Select internationalisation properties.
  programs.fish.enable = true;
  programs.zsh.enable = true;
  security.polkit.enable = true;

  services.meshcentral.enable = true;

  # Enable the X11 windowing system.

  # Enable the GNOME Desktop Environment.
  environment.pathsToLink = [ "/libexec" ];
  services.xserver.videoDrivers = [ "nvidia" ];
  services.xserver.xkb.variant = "us";
  # Configure keymap in X11
  services.mysql = {
    enable = true;
    package = pkgs.mariadb;
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  services.openssh.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.kaki = {
    isNormalUser = true;
    description = "kaki";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
      "input"
    ];
    packages = with pkgs; [
      firefox
      gh
      lshw
      tldr
    ];
  };
  services.xserver.xkb.layout = "us";
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    #  wget
    nix-output-monitor
    dig
    git
    meshcentral
    tigervnc
    openssl
  ];

  system.stateVersion = "25.05"; # Did you read the comment?
}
