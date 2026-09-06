{
  pkgs,
  watariConfig,
}:
let
  inherit (pkgs) lib;
  home = watariConfig.home-manager.users.kaki;
  packageNamed = name: lib.filter (package: lib.getName package == name) home.home.packages;
  emacsFrame = lib.head (packageNamed "emacs-frame");
  emacsDaemonStatus = lib.head (packageNamed "emacs-daemon-status");
  emacsDaemonRestart = lib.head (packageNamed "emacs-daemon-restart");
  emacsClientApp = lib.head (packageNamed "emacs-client-app");
  daemonShim = home.home.file.".local/bin/emacs-daemon".source;
  expectedPackage = home.programs.emacs.finalPackage;
  expectedArguments = [
    "${home.home.homeDirectory}/.local/bin/emacs-daemon"
    "--fg-daemon"
  ];
in
assert home.services.emacs.enable;
assert home.services.emacs.package.outPath == expectedPackage.outPath;
assert home.launchd.agents.emacs.domain == "gui";
assert home.launchd.agents.emacs.config.ProgramArguments == expectedArguments;
assert !(lib.hasInfix "/nix/store/" (builtins.toJSON home.launchd.agents.emacs.config));
assert lib.length (packageNamed "emacs-frame") == 1;
assert lib.length (packageNamed "emacs-daemon-status") == 1;
assert lib.length (packageNamed "emacs-daemon-restart") == 1;
assert lib.length (packageNamed "emacs-client-app") == 1;
pkgs.runCommandLocal "emacs-daemon-darwin-smoke"
  {
    nativeBuildInputs = [ pkgs.file ];
  }
  ''
    set -euo pipefail

    test -x ${daemonShim}
    grep -qF 'export HERMES_MANAGED_EMACS_DAEMON=1' ${daemonShim}
    grep -qF 'export HERMES_MANAGED_EMACS_PACKAGE=${expectedPackage}' ${daemonShim}
    grep -qF '${expectedPackage}/Applications/Emacs.app/Contents/MacOS/Emacs' ${daemonShim}

    test -x ${emacsFrame}/bin/emacs-frame
    grep -qF '"${expectedPackage}/bin/emacsclient" --create-frame --no-wait' ${emacsFrame}/bin/emacs-frame
    test -x ${emacsDaemonStatus}/bin/emacs-daemon-status
    test -x ${emacsDaemonRestart}/bin/emacs-daemon-restart

    app='${emacsClientApp}/Applications/Emacs Client.app'
    executable="$app/Contents/MacOS/EmacsClient"
    test -x "$executable"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = \
      'dev.yus314.emacs-client'
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")" = \
      'EmacsClient'
    file_output="$(file "$executable")"
    [[ "$file_output" == *'Mach-O 64-bit'* ]]
    [[ "$file_output" == *'arm64'* ]]
    grep -aqF '${emacsFrame}/bin/emacs-frame' "$executable"

    mkdir -p "$out"
    printf '%s\n' '${expectedPackage}' > "$out/emacs-package"
    printf '%s\n' '${daemonShim}' > "$out/daemon-shim"
    printf '%s\n' '${emacsClientApp}' > "$out/client-app"
  ''
