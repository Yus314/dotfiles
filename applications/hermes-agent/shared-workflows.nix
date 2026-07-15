{
  lib,
  pkgs,
  ...
}:
let
  configPython = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  sharedSkillsScript = ./scripts/shared_skills_config.py;
  validatedSharedSkills = pkgs.runCommand "hermes-shared-skills" { } ''
    mkdir -p "$out"
    ${configPython}/bin/python ${sharedSkillsScript} \
      check-source \
      --shared-root ${./shared-skills} >"$out/.manifest.json"
    cp -R ${./shared-skills}/. "$out/"
  '';
in
{
  home.file = {
    ".hermes/scripts/profile_weekly_summary_bootstrap.py".source =
      ./scripts/profile_weekly_summary_bootstrap.py;
    ".hermes/scripts/profile_summary_source_check.py".source =
      ./scripts/profile_summary_source_check.py;
    ".hermes/scripts/shared_skills_config.py".source = sharedSkillsScript;
    ".local/share/hermes/shared-skills".source = validatedSharedSkills;
  };

  home.activation.hermesSharedSkillsConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    $DRY_RUN_CMD ${configPython}/bin/python ${sharedSkillsScript} \
      configure \
      --home "$HOME" \
      --shared-root "$HOME/.local/share/hermes/shared-skills"
  '';
}
