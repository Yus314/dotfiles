{
  lib,
  pkgs,
  ...
}:
let
  configPython = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  sharedSkillsScript = ./scripts/shared_skills_config.py;
  sharedSkillsRunner = pkgs.writeShellScript "shared-skills-config" ''
    exec ${configPython}/bin/python ${sharedSkillsScript} "$@"
  '';
  profileRegistryCheckRunner = pkgs.writeShellScript "profile-registry-check" ''
    exec ${configPython}/bin/python ${./scripts/profile_registry_check.py} "$@"
  '';
  kanbanDispatchConfigRunner = pkgs.writeShellScript "kanban-dispatch-config" ''
    exec ${configPython}/bin/python ${./scripts/kanban_dispatch_config.py} "$@"
  '';
  profileHandoffCheck = pkgs.writeShellScriptBin "profile-handoff-check" ''
    exec ${pkgs.coreutils}/bin/env \
      PYTHONPATH=${./scripts} \
      ${configPython}/bin/python ${./scripts/profile_handoff_check.py} "$@"
  '';
  profileConsult = pkgs.writeShellScriptBin "profile-consult" ''
    exec ${pkgs.coreutils}/bin/env \
      PYTHONPATH=${./scripts} \
      ${configPython}/bin/python ${./scripts/profile_consult.py} "$@"
  '';
  sharedSkillsUnitTests = pkgs.runCommand "hermes-shared-skills-tests" { src = ./.; } ''
    cp -R "$src" source
    chmod -R u+w source
    cd source
    PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=scripts:tests \
      ${configPython}/bin/python -m unittest \
      tests/test_shared_skills_config.py \
      tests/test_engineering_quality_core.py \
      tests/test_profile_exchange_schema.py \
      tests/test_profile_handoff_check.py \
      tests/test_profile_consult.py \
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
      --registry ${./profile-registry.json} \
      --shared-root ${./shared-skills} >"$out/.manifest.json"
    cp -R ${./shared-skills}/. "$out/"
  '';
in
{
  home.packages = [
    profileHandoffCheck
    profileConsult
  ];

  home.file = {
    ".hermes/scripts/shared_skills_config.py".source = sharedSkillsRunner;
    ".local/share/hermes/shared-skills".source = validatedSharedSkills;
    ".local/share/hermes/profile-registry.json".source = ./profile-registry.json;
    ".hermes/profiles/finance/honcho.json".source = ./profile-configs/finance/honcho.json;
    ".hermes/profiles/food/honcho.json".source = ./profile-configs/food/honcho.json;
    ".hermes/profiles/health/honcho.json".source = ./profile-configs/health/honcho.json;
  };

  # Hermes rejects cron scripts whose resolved path escapes ~/.hermes/scripts.
  # Home Manager's normal home.file symlinks resolve into /nix/store, so install
  # cron scripts and their local validator module as regular files after link generation.
  home.activation.hermesCronScripts = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    $DRY_RUN_CMD mkdir -p "$HOME/.hermes/scripts"
    $DRY_RUN_CMD rm -f "$HOME/.hermes/scripts/profile_exchange_schema.py"
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0600 \
      ${./scripts/profile_exchange_schema.py} \
      "$HOME/.hermes/scripts/profile_exchange_schema.py"
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
      --registry "$HOME/.local/share/hermes/profile-registry.json" \
      --shared-root "$HOME/.local/share/hermes/shared-skills"
  '';

  home.activation.hermesProfilePolicyCheck =
    lib.hm.dag.entryAfter
      [
        "hermesCronScripts"
        "hermesMathProfile"
        "hermesSharedSkillsConfig"
      ]
      ''
        $DRY_RUN_CMD "$HOME/.hermes/scripts/profile_registry_check.py" \
          --registry "$HOME/.local/share/hermes/profile-registry.json" \
          --skip-gateways
      '';
}
