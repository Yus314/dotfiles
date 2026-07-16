#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
packages="$root/applications/emacs/elisp/packages"
tests="$root/applications/emacs/tests"

if [[ ${1:-} == "--benchmark" ]]; then
  if [[ $# -ne 1 ]]; then
    printf 'usage: %s [--benchmark]\n' "$0" >&2
    exit 2
  fi
  exec emacs --batch --quick \
    -L "$packages" -L "$tests" \
    -l "$tests/selection-batch-benchmark.el" \
    -f selection-batch-benchmark-run
elif [[ $# -ne 0 ]]; then
  printf 'usage: %s [--benchmark]\n' "$0" >&2
  exit 2
fi

exec emacs --batch --quick \
  -L "$packages" -L "$tests" \
  -l "$tests/selection-batch-load-test.el" \
  -l "$tests/selection-batch-core-test.el" \
  -l "$tests/selection-batch-plan-test.el" \
  -l "$tests/selection-batch-ui-test.el" \
  -l "$tests/selection-batch-operators-test.el" \
  -l "$tests/selection-batch-integration-test.el" \
  -f ert-run-tests-batch-and-exit
