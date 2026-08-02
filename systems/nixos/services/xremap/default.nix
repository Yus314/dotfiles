{
  inputs,
  lib,
  config,
  ...
}:
let
  inherit (inputs) xremap;
in
{
  imports = [
    xremap.nixosModules.default
  ];
  services.xremap = {
    # Lawliet's Corne has migrated to the host-specific Kanata service. Keep
    # xremap on the other NixOS hosts until they are migrated independently.
    enable = config.networking.hostName != "lawliet";
    withWlroots = true;
    yamlConfig =
      let
        remapFiles = [ ./shingeta.yml ] ++ lib.optional (config.networking.hostName == "ryuk") ./hhkb.yaml;
        remapContents = map builtins.readFile remapFiles;
      in
      lib.concatStringsSep "\n" remapContents;
  };

  boot.kernelModules = [ "uinput" ];
  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="input", TAG+="uaccess"
  '';

}
