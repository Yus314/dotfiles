{ lib, ... }:
{
  # Stage 1 of the xremap -> Kanata migration.  Keep the unit declarative and
  # build-checked, but do not start it automatically while xremap remains the
  # production input path.
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
    # A manual start stops xremap through Conflicts.  Until the rollout gate,
    # use only the bounded canary wrapper that pre-arms automatic rollback.
    wantedBy = lib.mkForce [ ];
    conflicts = [ "xremap.service" ];
  };
}
