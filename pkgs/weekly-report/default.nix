{
  writeShellScriptBin,
  emacs,
  coreutils,
}:

writeShellScriptBin "generate-weekly-report" ''
  set -euo pipefail

  # Verify org directory exists
  if [ ! -d "$HOME/org/inbox" ]; then
    echo "Error: ~/org/inbox not found." >&2
    exit 1
  fi

  exec ${emacs}/bin/emacs --batch \
    --eval "(setq gc-cons-threshold (* 50 1000 1000))" \
    -l ${./weekly-report.el} \
    --eval "(weekly-report-generate)" \
    -- "$@"
''
