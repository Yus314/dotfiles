{ inputs, pkgs }:
let
  inherit (pkgs) lib;
  actualPkgs = import ../emacs-toolchain.nix {
    inherit inputs;
    system = pkgs.stdenv.hostPlatform.system;
  };
  actualEmacs =
    (import ../../emacs-minimal/emacspkg/default.nix { pkgs = actualPkgs; }).emacs-unstable;
  home = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inherit inputs; };
    modules = [
      ../../emacs-minimal/default.nix
      ../../emacs-minimal/service.nix
      (
        { lib, ... }:
        {
          home = {
            username = "selection-batch-minimal-package-smoke";
            homeDirectory = "/tmp/selection-batch-minimal-package-smoke";
            stateVersion = "24.05";
            packages = lib.mkForce [ ];
          };
          programs.emacs = {
            package = lib.mkForce actualEmacs;
            selectionFirst.enable = true;
          };
        }
      )
    ];
  };
  emacsFiles = lib.filterAttrs (path: _: lib.hasPrefix "emacs/" path) home.config.xdg.configFile;
  configTree = pkgs.linkFarm "selection-batch-minimal-package-emacs" (
    lib.mapAttrsToList (path: file: {
      name = lib.removePrefix "emacs/" path;
      path = file.source;
    }) emacsFiles
  );
  fixture = ./selection-first-minimal-configured-smoke-test.el;
  standaloneFixture = ./selection-batch-minimal-smoke-test.el;
in
assert home.config.programs.emacs.package.outPath == actualEmacs.outPath;
assert
  home.config.services.emacs.package.outPath == home.config.programs.emacs.finalPackage.outPath;
pkgs.runCommandLocal "selection-batch-minimal-package-smoke"
  {
    nativeBuildInputs = [ home.config.programs.emacs.finalPackage ];
  }
  ''
    set -euo pipefail

    test_home="$(mktemp -d "$TMPDIR/selection-batch-minimal-package-home.XXXXXX")"
    cleanup() {
      chmod -R u+w "$test_home" 2>/dev/null || true
      rm -rf "$test_home"
    }
    trap cleanup EXIT
    export HOME="$test_home"
    export XDG_CONFIG_HOME="$HOME/.config"
    mkdir -p "$XDG_CONFIG_HOME"
    ln -s ${configTree} "$XDG_CONFIG_HOME/emacs"

    emacs --batch --quick \
      --load ${standaloneFixture} \
      --funcall ert-run-tests-batch-and-exit \
      2>&1 | tee standalone-smoke.log

    emacs --batch --quick \
      --eval '(unless (>= emacs-major-version 31) (error "Emacs 31 required, got %s" emacs-version))' \
      --load "$XDG_CONFIG_HOME/emacs/init.el" \
      --load ${fixture} \
      --funcall ert-run-tests-batch-and-exit \
      2>&1 | tee package-smoke.log

    mkdir -p "$out"
    cp package-smoke.log "$out/test.log"
    cp standalone-smoke.log "$out/standalone-test.log"
    printf '%s\n' ${actualEmacs} > "$out/emacs-package"
    printf '%s\n' ${home.config.programs.emacs.finalPackage} > "$out/final-package"
    printf '%s\n' ${home.config.services.emacs.package} > "$out/service-package"
  ''
