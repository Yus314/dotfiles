{ config, pkgs, ... }:
{
  sops.secrets.kaki-password-hash.neededForUsers = true;

  users.users.kaki = {
    isNormalUser = true;
    description = "kaki";
    shell = pkgs.fish;
    hashedPasswordFile = config.sops.secrets.kaki-password-hash.path;
    extraGroups = [
      "networkmanager"
      "wheel"
      "input"
      "docker"
      "adbusers"
    ];
  };
}
