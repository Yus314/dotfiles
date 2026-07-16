#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
packages="$root/applications/emacs/elisp/packages"
tests="$root/applications/emacs/tests"

exec emacs --batch --quick \
  -L "$packages" -L "$tests" \
  -l "$tests/selection-batch-load-test.el" \
  -l "$tests/selection-batch-core-test.el" \
  -l "$tests/selection-batch-plan-test.el" \
  -l "$tests/selection-batch-ui-test.el" \
  -l "$tests/selection-batch-operators-test.el" \
  -l "$tests/selection-batch-integration-test.el" \
  -f ert-run-tests-batch-and-exit
