#  Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  inputs,
  config,
  pkgs,
  unstable,
  emacs-overlay,
  org-babel,
  bizin-gothic-discord,
  xremap,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./host/lab-main-hardware-configuration.nix
	./greetd.nix
  ];
  fonts.packages = [ bizin-gothic-discord ];
  fonts.fontDir.enable = true;

  console.keyMap = "dvorak";
  users.users.Cloudflared = {
    group = "wheel";
    isSystemUser = true;
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

  systemd.services.lab2home = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token=eyJhIjoiZTU4ODdmZDg4NDFmZjRmZDQzZTQ2Y2QxZTAxYjM4MDkiLCJ0IjoiMGMzYzdiNmQtZDY1Yy00MTM0LWJiY2QtMzkzMDM4M2M4OGQ3IiwicyI6IllXTTNaalppTmpFdFpEZzJZUzAwTm1JMExUazJZekV0T0dKbE5HTTBOemRoTVRoaiJ9";
      Restart = "always";
      User = "kaki";
      Group = "wheel";
    };
  };

  # Bootloader
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      #    access-tokens = ;
    };
  };
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
  home-manager = {
    users.kaki = {
      imports = [
        ./home-manager/NixOS/gui
        ./home-manager/NixOS/cli
        ./home-manager/common
      ];
      home = {
        username = "kaki";
        homeDirectory = "/home/kaki";
        stateVersion = "24.11";
      };
      nixpkgs.config.allowUnfree = true;
      nixpkgs.overlays = [ emacs-overlay.overlays.emacs ];
    };
    backupFileExtension = "buckup";
    # useGlobalPkgs = true;
    # useUserPackages = true;
    extraSpecialArgs = {
      inherit unstable;
      inherit org-babel;
      inherit xremap;
    };
  };
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowBroken = true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.extraModulePackages = with config.boot.kernelPackages; [
    r8125
    nvidia_x11
  ];
  boot.kernelModules = [ "r8125" ];
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
  networking.hostName = "lab-main"; # Define your hostname.
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
  users.users.kaki.shell = pkgs.bash;
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
    ];
    packages = with pkgs; [
      firefox
      gh
      lshw
      tldr
    ];
  };
  services.xserver.xkb.layout = "us";
  # List packages installed in system profile. To search, run:
  # $ nix search wget
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

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
