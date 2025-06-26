{
  inputs,
  config,
  lib,
  ...
}:
let
  # hydra doesn't support ssh-ng protocol
  # https://github.com/NixOS/hydra/issues/688
  protocol = if (config.services ? hydra && config.services.hydra.enable) then "ssh" else "ssh-ng";
  inherit (inputs.self.outputs.nixosConfigurations) ryuk rem;
in
{
  nix = {
    distributedBuilds = true;

    extraOptions = ''
      builders-use-substitutes = true
    '';

    buildMachines =
      [ ]
      ++ lib.optional (config.networking.hostName != "ryuk") {
        inherit (ryuk.config.networking) hostName;
        systems = [
          "x86_64-linux"
        ];
        sshUser = "kaki";
        inherit protocol;
        maxJobs = ryuk.config.nix.settings.max-jobs;
        speedFactor = 1;
        supportedFeatures = ryuk.config.nix.settings.system-features;
        mandatoryFeatures = [ ];
      }
      ++ lib.optional (config.networking.hostName != "rem") {
        inherit (rem.config.networking) hostName;
        systems = [
          "x86_64-linux"
        ];
        sshUser = "kaki";
        inherit protocol;
        maxJobs = rem.config.nix.settings.max-jobs;
        speedFactor = 1;
        supportedFeatures = rem.config.nix.settings.system-features;
        mandatoryFeatures = [ ];
      };
  };
}
