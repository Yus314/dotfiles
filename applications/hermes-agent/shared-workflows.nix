{
  lib,
  pkgs,
  ...
}:
let
  configPython = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  sharedSkillsScript = ./scripts/shared_skills_config.py;
  profileRegistryCheckRunner = pkgs.writeShellScript "profile-registry-check" ''
    exec ${configPython}/bin/python ${./scripts/profile_registry_check.py} "$@"
  '';
  kanbanDispatchConfigRunner = pkgs.writeShellScript "kanban-dispatch-config" ''
    exec ${configPython}/bin/python ${./scripts/kanban_dispatch_config.py} "$@"
  '';
  sharedSkillsUnitTests = pkgs.runCommand "hermes-shared-skills-tests" { src = ./.; } ''
    cp -R "$src" source
    chmod -R u+w source
    cd source
    PYTHONDONTWRITEBYTECODE=1 ${configPython}/bin/python -m unittest \
      tests/test_shared_skills_config.py \
      tests/test_profile_summary_source_check.py \
      tests/test_profile_registry_check.py \
      tests/test_kanban_dispatch_config.py \
      tests/test_usage_analysis_shared.py \
      tests/test_usage_adapters.py \
      tests/test_gateway_channels_config.py \
      tests/test_gateway_preflight.py \
      tests/test_research_config.py
    touch "$out"
  '';
  validatedSharedSkills = pkgs.runCommand "hermes-shared-skills" { } ''
    test -e ${sharedSkillsUnitTests}
    mkdir -p "$out"
    ${configPython}/bin/python ${sharedSkillsScript} \
      check-source \
      --shared-root ${./shared-skills} >"$out/.manifest.json"
    cp -R ${./shared-skills}/. "$out/"
  '';
in
{
  home.file = {
    ".hermes/scripts/shared_skills_config.py".source = sharedSkillsScript;
    ".local/share/hermes/shared-skills".source = validatedSharedSkills;
    ".local/share/hermes/profile-registry.json".source = ./profile-registry.json;
  };

  # Hermes rejects cron scripts whose resolved path escapes ~/.hermes/scripts.
  # Home Manager's normal home.file symlinks resolve into /nix/store, so install
  # these two scripts as regular files after link generation instead.
  home.activation.hermesCronScripts = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    $DRY_RUN_CMD mkdir -p "$HOME/.hermes/scripts"
    $DRY_RUN_CMD rm -f "$HOME/.hermes/scripts/profile_weekly_summary_bootstrap.py"
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0700 \
      ${./scripts/profile_weekly_summary_bootstrap.py} \
      "$HOME/.hermes/scripts/profile_weekly_summary_bootstrap.py"
    $DRY_RUN_CMD rm -f "$HOME/.hermes/scripts/profile_summary_source_check.py"
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0700 \
      ${./scripts/profile_summary_source_check.py} \
      "$HOME/.hermes/scripts/profile_summary_source_check.py"
    $DRY_RUN_CMD rm -f "$HOME/.hermes/scripts/profile_registry_check.py"
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0700 \
      ${profileRegistryCheckRunner} \
      "$HOME/.hermes/scripts/profile_registry_check.py"
    $DRY_RUN_CMD rm -f "$HOME/.hermes/scripts/kanban_dispatch_config.py"
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0700 \
      ${kanbanDispatchConfigRunner} \
      "$HOME/.hermes/scripts/kanban_dispatch_config.py"
    $DRY_RUN_CMD "$HOME/.hermes/scripts/kanban_dispatch_config.py" configure \
      --registry "$HOME/.local/share/hermes/profile-registry.json"
  '';

  home.activation.hermesSharedSkillsConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    $DRY_RUN_CMD ${configPython}/bin/python ${sharedSkillsScript} \
      configure \
      --home "$HOME" \
      --shared-root "$HOME/.local/share/hermes/shared-skills"
  '';

  home.activation.hermesProfilePolicyCheck =
    lib.hm.dag.entryAfter
      [
        "hermesCronScripts"
        "hermesSharedSkillsConfig"
      ]
      ''
        $DRY_RUN_CMD "$HOME/.hermes/scripts/profile_registry_check.py" \
          --registry "$HOME/.local/share/hermes/profile-registry.json" \
          --skip-gateways
      '';
}
