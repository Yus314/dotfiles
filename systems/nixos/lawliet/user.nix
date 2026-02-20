{ pkgs, ... }:
{
  users.users.kaki = {
    isNormalUser = true;
    description = "kaki";
    shell = pkgs.fish;
    extraGroups = [
      "networkmanager"
      "wheel"
      "input"
      "docker"
      "adbusers"
    ];
  };
}
