{
  config,
  lib,
  pkgs,
  ...
}:
let
  stateDir = "${config.xdg.stateHome}/omniwm";
  omniwmRecover = pkgs.writeShellScriptBin "omniwm-recover" ''
    set -eu
    umask 077

    omniwmctl=${lib.escapeShellArg "${pkgs.omniwm}/bin/omniwmctl"}
    jq=${lib.escapeShellArg (lib.getExe pkgs.jq)}
    label="gui/$(/usr/bin/id -u)/org.nix-community.home.omniwm"
    timestamp="$(/bin/date '+%Y%m%d-%H%M%S')"
    recovery_dir=${lib.escapeShellArg "${stateDir}/recovery"}/"$timestamp"
    /bin/mkdir -p "$recovery_dir"

    capture_state() {
      phase=$1
      phase_dir="$recovery_dir/$phase"
      /bin/mkdir -p "$phase_dir"

      "$omniwmctl" query windows --format json \
        > "$phase_dir/windows.json" 2> "$phase_dir/windows.error" || true
      "$omniwmctl" query workspaces --format json \
        > "$phase_dir/workspaces.json" 2> "$phase_dir/workspaces.error" || true
      "$omniwmctl" query displays --format json \
        > "$phase_dir/displays.json" 2> "$phase_dir/displays.error" || true

      if [ -f ${lib.escapeShellArg "${stateDir}/runtime-state.json"} ]; then
        /bin/cp ${lib.escapeShellArg "${stateDir}/runtime-state.json"} \
          "$phase_dir/runtime-state.json"
      fi
    }

    capture_state before
    /bin/launchctl kickstart -k "$label"

    attempt=0
    while [ "$attempt" -lt 50 ]; do
      if "$omniwmctl" ping >/dev/null 2>&1; then
        break
      fi
      attempt=$((attempt + 1))
      /bin/sleep 0.1
    done

    if [ "$attempt" -ge 50 ]; then
      printf 'OmniWM did not become ready; diagnostics: %s\n' "$recovery_dir" >&2
      exit 1
    fi

    # IPC becomes available before OmniWM finishes its initial window rescan.
    # Wait for the live inventory so the post-recovery capture is meaningful.
    settle_attempt=0
    while [ "$settle_attempt" -lt 50 ]; do
      if "$omniwmctl" query windows --format json 2>/dev/null \
        | "$jq" -e '.result.payload.windows | length > 0' >/dev/null 2>&1; then
        break
      fi
      settle_attempt=$((settle_attempt + 1))
      /bin/sleep 0.1
    done

    capture_state after
    printf 'OmniWM recovered; diagnostics: %s\n' "$recovery_dir"
  '';
in
{
  home.packages = [
    pkgs.omniwm
    omniwmRecover
  ];

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
