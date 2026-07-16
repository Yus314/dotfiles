{
  inputs,
  pkgs,
}:
let
  testPkgs = pkgs.extend inputs.emacs-overlay.overlays.default;
  inherit (testPkgs) lib;

  baseEmacs = if testPkgs.stdenv.hostPlatform.isLinux then testPkgs.emacs-nox else testPkgs.emacs;
  emacs = (testPkgs.emacsPackagesFor baseEmacs).emacsWithPackages (epkgs: [
    epkgs.meow
    epkgs.puni
  ]);

  home = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = testPkgs;
    extraSpecialArgs = { inherit inputs; };
    modules = [
      ../default.nix
      (
        { lib, ... }:
        {
          home = {
            username = "selection-batch-smoke";
            homeDirectory = "/tmp/selection-batch-smoke";
            stateVersion = "24.05";
            packages = lib.mkForce [ ];
          };
          programs.emacs.package = lib.mkForce emacs;
        }
      )
    ];
  };

  emacsFiles = lib.filterAttrs (name: _: lib.hasPrefix "emacs/" name) home.config.xdg.configFile;
  configTree = pkgs.linkFarm "selection-batch-configured-emacs" (
    lib.mapAttrsToList (name: file: {
      name = lib.removePrefix "emacs/" name;
      path = file.source;
    }) emacsFiles
  );
  fixture = ./selection-batch-configured-smoke-test.el;
in
assert home.config.programs.emacs.package.outPath == emacs.outPath;
assert home.config.home.packages == [ ];
pkgs.runCommandLocal "selection-batch-configured-smoke" { nativeBuildInputs = [ emacs ]; } ''
  set -euo pipefail

  test_home="$(mktemp -d "$TMPDIR/selection-batch-home.XXXXXX")"
  cleanup() {
    chmod -R u+w "$test_home" 2>/dev/null || true
    rm -rf "$test_home"
  }
  trap cleanup EXIT

  export HOME="$test_home"
  export XDG_CONFIG_HOME="$HOME/.config"
  mkdir -p "$XDG_CONFIG_HOME"
  ln -s ${configTree} "$XDG_CONFIG_HOME/emacs"

  test -f "$XDG_CONFIG_HOME/emacs/init.el"
  test -f "$XDG_CONFIG_HOME/emacs/modules/init-selection-batch.el"
  test -f "$XDG_CONFIG_HOME/emacs/packages/selection-batch.el"

  # Load the real editing module and then selection-batch through generated
  # init.el, while skipping only unrelated full-desktop modules.
  emacs --batch --quick \
    --eval '(require '\'''meow)' \
    --eval '(advice-add '\'''require :around (lambda (original feature &rest args) (if (and (string-prefix-p "init-" (symbol-name feature)) (not (memq feature '\'''(init-editing init-selection-batch)))) t (apply original feature args))))' \
    --load "$XDG_CONFIG_HOME/emacs/init.el" \
    --load ${fixture} \
    --funcall ert-run-tests-batch-and-exit \
    2>&1 | tee configured-smoke.log

  mkdir -p "$out"
  cp configured-smoke.log "$out/test.log"
  printf '%s\n' ${configTree} > "$out/config-tree"
''
