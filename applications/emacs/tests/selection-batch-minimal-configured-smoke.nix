{
  inputs,
  pkgs,
}:
let
  inherit (pkgs) lib;
  actualPkgs = import ../emacs-toolchain.nix {
    inherit inputs;
    system = pkgs.stdenv.hostPlatform.system;
  };
  emacs = (import ../../emacs-minimal/emacspkg/default.nix { pkgs = actualPkgs; }).emacs-unstable;

  mkHome =
    enabled:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit inputs; };
      modules = [
        ../../emacs-minimal/default.nix
        ../../emacs-minimal/service.nix
        (
          { lib, ... }:
          {
            home = {
              username = "selection-batch-minimal-smoke";
              homeDirectory = "/tmp/selection-batch-minimal-smoke";
              stateVersion = "24.05";
              packages = lib.mkForce [ ];
            };
            programs.emacs = {
              package = lib.mkForce emacs;
              selectionFirst.enable = enabled;
            };
          }
        )
      ];
    };

  enabledHome = mkHome true;
  disabledHome = mkHome false;
  mkConfigTree =
    name: home:
    let
      emacsFiles = lib.filterAttrs (path: _: lib.hasPrefix "emacs/" path) home.config.xdg.configFile;
    in
    pkgs.linkFarm name (
      lib.mapAttrsToList (path: file: {
        name = lib.removePrefix "emacs/" path;
        path = file.source;
      }) emacsFiles
    );
  enabledConfigTree = mkConfigTree "selection-batch-minimal-enabled-emacs" enabledHome;
  disabledConfigTree = mkConfigTree "selection-batch-minimal-disabled-emacs" disabledHome;
  fixture = ./selection-first-minimal-configured-smoke-test.el;
in
assert enabledHome.config.programs.emacs.package.outPath == emacs.outPath;
assert disabledHome.config.programs.emacs.package.outPath == emacs.outPath;
assert
  enabledHome.config.services.emacs.package.outPath
  == enabledHome.config.programs.emacs.finalPackage.outPath;
assert
  disabledHome.config.services.emacs.package.outPath
  == disabledHome.config.programs.emacs.finalPackage.outPath;
assert enabledHome.config.home.packages == [ ];
assert disabledHome.config.home.packages == [ ];
pkgs.runCommandLocal "selection-batch-minimal-configured-smoke" { nativeBuildInputs = [ emacs ]; }
  ''
    set -euo pipefail

    test_home="$(mktemp -d "$TMPDIR/selection-batch-minimal-home.XXXXXX")"
    cleanup() {
      chmod -R u+w "$test_home" 2>/dev/null || true
      rm -rf "$test_home"
    }
    trap cleanup EXIT

    export HOME="$test_home"
    export XDG_CONFIG_HOME="$HOME/.config"
    mkdir -p "$XDG_CONFIG_HOME"
    ln -s ${enabledConfigTree} "$XDG_CONFIG_HOME/emacs"

    test -f "$XDG_CONFIG_HOME/emacs/init.el"
    test -f "$XDG_CONFIG_HOME/emacs/modules/init-editing.el"
    test -f "$XDG_CONFIG_HOME/emacs/modules/init-selection-batch.el"
    test -f "$XDG_CONFIG_HOME/emacs/packages/selection-batch.el"
    test -f "$XDG_CONFIG_HOME/emacs/packages/selection-first.el"

    check_lexical_cookie() {
      local file="$1" first
      IFS= read -r first < "$file"
      if [[ "$first" != ';;; -*- lexical-binding: t; -*-' ]]; then
        printf 'invalid first-line lexical-binding cookie: %s: %s\n' "$file" "$first" >&2
        return 1
      fi
    }
    for file in \
      "$XDG_CONFIG_HOME/emacs/init.el" \
      "$XDG_CONFIG_HOME/emacs/early-init.el" \
      "$XDG_CONFIG_HOME/emacs/modules/"*.el; do
      check_lexical_cookie "$file"
    done

    emacs --batch --quick \
      --load "$XDG_CONFIG_HOME/emacs/init.el" \
      --load ${fixture} \
      --funcall ert-run-tests-batch-and-exit \
      2>&1 | tee configured-smoke.log

    rm "$XDG_CONFIG_HOME/emacs"
    ln -s ${disabledConfigTree} "$XDG_CONFIG_HOME/emacs"

    for file in \
      "$XDG_CONFIG_HOME/emacs/init.el" \
      "$XDG_CONFIG_HOME/emacs/early-init.el" \
      "$XDG_CONFIG_HOME/emacs/modules/"*.el; do
      check_lexical_cookie "$file"
    done

    emacs --batch --quick \
      --load "$XDG_CONFIG_HOME/emacs/init.el" \
      --eval '(unless (and meow-global-mode (not selection-first-global-mode) (not selection-batch-enable-meow-bindings)) (error "selection-first rollback flag failed"))' \
      2>&1 | tee -a configured-smoke.log

    mkdir -p "$out"
    cp configured-smoke.log "$out/test.log"
    printf '%s\n' ${enabledConfigTree} > "$out/enabled-config-tree"
    printf '%s\n' ${disabledConfigTree} > "$out/disabled-config-tree"
  ''
