{ config, ... }:
{

  boot.extraModulePackages = with config.boot.kernelPackages; [
    # r8125
    nvidia_x11
  ];
  boot.initrd.kernelModules = [ "nvidia" ];
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.production;
  };
}
