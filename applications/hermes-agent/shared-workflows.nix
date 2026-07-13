{
  lib,
  pkgs,
  ...
}:
let
  configPython = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
in
{
  home.file = {
    ".hermes/scripts/profile_weekly_summary_bootstrap.py".source =
      ./scripts/profile_weekly_summary_bootstrap.py;
    ".hermes/scripts/profile_summary_source_check.py".source =
      ./scripts/profile_summary_source_check.py;
    ".local/share/hermes/shared-skills".source = ./shared-skills;
  };

  home.activation.hermesSharedSkillsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${configPython}/bin/python - <<'PY'
    from pathlib import Path
    import os
    import tempfile
    import yaml

    def write_yaml_atomic(path, value):
        rendered = yaml.safe_dump(value, sort_keys=False, allow_unicode=True)
        original_mode = path.stat().st_mode & 0o777
        fd, temporary_name = tempfile.mkstemp(
            dir=path.parent,
            prefix=f".{path.name}.",
            text=True,
        )
        temporary_path = Path(temporary_name)
        try:
            with os.fdopen(fd, "w") as handle:
                handle.write(rendered)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temporary_path, original_mode)
            os.replace(temporary_path, path)
        finally:
            temporary_path.unlink(missing_ok=True)

    shared_root = Path.home() / ".local/share/hermes/shared-skills"
    shared_groups = {
        "common": str(shared_root / "common"),
        "study": str(shared_root / "study"),
        "engineering": str(shared_root / "engineering"),
        "profile-ops": str(shared_root / "profile-ops"),
    }
    profile_groups = {
        "default": ("common", "study", "engineering", "profile-ops"),
        "career": ("common", "study", "engineering"),
        "economics": ("common", "study"),
        "english": ("common", "study"),
        "finance": ("common",),
        "food": ("common",),
        "health": ("common",),
        "indiedev": ("common", "engineering"),
        "math": ("common", "study"),
        "researcheval": ("common", "engineering"),
    }
    managed_dirs = {str(shared_root), *shared_groups.values()}

    for profile_name, groups in profile_groups.items():
        profile_home = (
            Path.home() / ".hermes"
            if profile_name == "default"
            else Path.home() / ".hermes/profiles" / profile_name
        )
        cfg_path = profile_home / "config.yaml"
        if not cfg_path.exists():
            continue
        cfg = yaml.safe_load(cfg_path.read_text())
        if not isinstance(cfg, dict):
            cfg = {}
        skills = cfg.setdefault("skills", {})
        if not isinstance(skills, dict):
            skills = {}
            cfg["skills"] = skills
        external_dirs = skills.get("external_dirs", [])
        if not isinstance(external_dirs, list):
            external_dirs = []
        unmanaged_dirs = [
            value for value in external_dirs
            if value not in managed_dirs
        ]
        skills["external_dirs"] = [
            *[shared_groups[group] for group in groups],
            *unmanaged_dirs,
        ]
        write_yaml_atomic(cfg_path, cfg)
    PY
  '';
}
