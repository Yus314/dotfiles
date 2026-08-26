{
  config,
  lib,
  pkgs,
  ...
}:
let
  stateDir = "${config.xdg.stateHome}/omniwm";
in
{
  home.packages = [ pkgs.omniwm ];

  # OmniWM's settings UI writes this file imperatively. Keep the qualified
  # watari configuration reproducible and make the Nix source authoritative.
  xdg.configFile."omniwm/settings.toml" = {
    source = ./settings.toml;
    force = true;
  };

  home.activation.omniwmStateDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg stateDir}
  '';

  # Keep trial startup declarative and avoid OmniWM's separate login-item path.
  launchd.agents.omniwm = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.omniwm}/Applications/OmniWM.app/Contents/MacOS/OmniWM"
      ];
      RunAtLoad = true;
      KeepAlive = false;
      ProcessType = "Interactive";
      StandardOutPath = "${stateDir}/launchd.log";
      StandardErrorPath = "${stateDir}/launchd-error.log";
    };
  };
}
