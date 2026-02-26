{
  writeShellScriptBin,
  emacs,
  coreutils,
}:

writeShellScriptBin "generate-weekly-report" ''
  set -euo pipefail

  # Verify Dropbox is mounted
  if [ ! -d "$HOME/dropbox/inbox" ]; then
    echo "Error: ~/dropbox/inbox not found. Is Dropbox mounted?" >&2
    exit 1
  fi

  exec ${emacs}/bin/emacs --batch \
    --eval "(setq gc-cons-threshold (* 50 1000 1000))" \
    -l ${./weekly-report.el} \
    --eval "(weekly-report-generate)" \
    -- "$@"
''
