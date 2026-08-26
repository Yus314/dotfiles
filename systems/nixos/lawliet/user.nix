{ config, pkgs, ... }:
{
  sops.secrets.kaki-password-hash.neededForUsers = true;

  users.users.kaki = {
    isNormalUser = true;
    description = "kaki";
    shell = pkgs.fish;
    hashedPasswordFile = config.sops.secrets.kaki-password-hash.path;
    openssh.authorizedKeys.keys = [
      "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAHvJKRmO1WHVDdcPTyc7E7t0nLA8QNLt6SqrYC0zCLPP71J7gul03nNwPObQV57H/so1Fgds/tA4NZCAOxDBPmjXwAZG1z6bi/uzUcvviFGZftuh8zB4+jNyZ7yoJZNIpOZNz0Miyo46qg+FSygVmAknxmabh/zvKyDIiv4lpW+8Iz2Vw== openpgp:0x20CB7E85"
    ];
    extraGroups = [
      "networkmanager"
      "wheel"
      "input"
      "docker"
      "adbusers"
    ];
  };
}
