{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  configPython = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);
  codexConfigDir =
    if config.home.preferXdgDirectories then
      "${config.xdg.configHome}/codex"
    else
      "${config.home.homeDirectory}/.codex";
in
{
  programs.herdr = {
    enable = true;
    package = inputs.herdr-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;

    settings.ui = {
      agent_panel_sort = "priority";
      status_indicators = "symbols";
      toast = {
        delivery = "herdr";
        delay_seconds = 1;
      };
    };
  };

  # Keep the generated settings as the declarative source, but merge only those
  # keys into a writable file so onboarding, custom keys and Settings still work.
  xdg.configFile."herdr/config.toml".enable = false;
  home.activation.herdrMutableConfig =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        run ${configPython}/bin/python ${../codex/mutable_config.py} \
          ${config.xdg.configFile."herdr/config.toml".source} \
          ${lib.escapeShellArg "${config.xdg.configHome}/herdr/config.toml"}
      '';

  # Supply python3 for the official hook without overriding an existing Python
  # environment or colliding with its executables in the Home Manager profile.
  home.packages = lib.mkIf config.programs.codex.enable [ (lib.lowPrio pkgs.python3) ];

  # Use the installer bundled with the pinned package: it merges Herdr's hook
  # entries while retaining other hooks and mutable Codex settings. Wait until
  # the writable config has been materialized and Home Manager has linked files.
  home.activation.herdrCodexIntegration = lib.mkIf config.programs.codex.enable (
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "codexMutableConfig"
        "linkGeneration"
      ]
      ''
        run ${pkgs.coreutils}/bin/env \
          CODEX_HOME=${lib.escapeShellArg codexConfigDir} \
          ${config.programs.herdr.package}/bin/herdr integration install codex
      ''
  );
}
