{ ... }:
{
  # Production Corne input path. xremap remains available in previous NixOS
  # generations and on hosts that have not migrated.
  services.kanata = {
    enable = true;
    keyboards.corne = {
      devices = [
        "/dev/input/by-id/usb-foostan_Corne-event-kbd"
        "/dev/input/by-id/usb-foostan_Corne-if01-event-kbd"
      ];
      extraDefCfg = ''
        process-unmapped-keys yes
        concurrent-tap-hold yes
      '';
      config = builtins.readFile ./shingeta.kbd;
      port = null;
    };
  };

  systemd.services.kanata-corne = {
    conflicts = [ "xremap.service" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "2s";
    };
  };
}
