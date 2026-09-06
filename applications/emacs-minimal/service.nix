{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  emacsPackage = config.programs.emacs.finalPackage;
  emacsClient = "${emacsPackage}/bin/emacsclient";
  launchdLabel = "org.nix-community.home.emacs";
  stableDarwinDaemon = "${config.home.homeDirectory}/.local/bin/emacs-daemon";
  managedDaemonElisp = ''(and (daemonp) (equal (getenv "HERMES_MANAGED_EMACS_DAEMON") "1"))'';
  currentManagedDaemonElisp = ''(and ${managedDaemonElisp} (equal (getenv "HERMES_MANAGED_EMACS_PACKAGE") "${emacsPackage}"))'';

  startManagedDaemon =
    if isDarwin then
      ''/bin/launchctl kickstart "gui/$(/usr/bin/id -u)/${launchdLabel}"''
    else
      "${pkgs.systemd}/bin/systemctl --user start emacs.service";

  waitForDaemon = ''
    daemon_ready() {
      [[ "$("${emacsClient}" --eval '${currentManagedDaemonElisp}' 2>/dev/null || true)" == "t" ]]
    }

    wait_for_daemon() {
      for _attempt in {1..300}; do
        if daemon_ready; then
          return 0
        fi
        ${pkgs.coreutils}/bin/sleep 0.1
      done
      return 1
    }
  '';

  darwinDaemonShim = pkgs.writeShellApplication {
    name = "emacs-daemon";
    text = ''
      export HERMES_MANAGED_EMACS_DAEMON=1
      export HERMES_MANAGED_EMACS_PACKAGE=${emacsPackage}
      exec ${emacsPackage}/Applications/Emacs.app/Contents/MacOS/Emacs "$@"
    '';
  };

  emacsFrame = pkgs.writeShellApplication {
    name = "emacs-frame";
    text = ''
      ${waitForDaemon}

      if ! daemon_ready; then
        ${startManagedDaemon}
        if ! wait_for_daemon; then
          printf 'emacs-frame: managed Emacs daemon did not become ready\n' >&2
          exit 1
        fi
      fi

      exec "${emacsClient}" --create-frame --no-wait "$@"
    '';
  };

  emacsDaemonStatus = pkgs.writeShellApplication {
    name = "emacs-daemon-status";
    text = ''
      printf 'expected-package=%s\n' '${emacsPackage}'
      if ! result=$("${emacsClient}" --eval \
        '(list :daemonp (daemonp) :managed (equal (getenv "HERMES_MANAGED_EMACS_DAEMON") "1") :package (getenv "HERMES_MANAGED_EMACS_PACKAGE") :pid (emacs-pid) :version emacs-version :site-lisp (getenv "emacsWithPackages_siteLisp") :exec-path-from-shell (locate-library "exec-path-from-shell") :lsp-mode (locate-library "lsp-mode") :lean4-mode (locate-library "lean4-mode"))' \
        2>/dev/null); then
        printf 'server=unreachable\n'
        exit 1
      fi
      printf 'server=reachable\n%s\n' "$result"
      if [[ "$("${emacsClient}" --eval '${currentManagedDaemonElisp}' 2>/dev/null || true)" != "t" ]]; then
        printf 'server=unexpected-owner-or-package\n' >&2
        exit 1
      fi
    '';
  };

  emacsDaemonRestart = pkgs.writeShellApplication {
    name = "emacs-daemon-restart";
    text = ''
      if [[ "$("${emacsClient}" --eval '${managedDaemonElisp}' 2>/dev/null || true)" != "t" ]]; then
        printf 'emacs-daemon-restart: managed Emacs daemon is not reachable\n' >&2
        exit 1
      fi

      old_pid=$("${emacsClient}" --eval '(emacs-pid)')
      stop_result=$("${emacsClient}" --eval \
        '(let ((modified (mapcar (function buffer-name) (seq-filter (lambda (buffer) (with-current-buffer buffer (let ((name (buffer-name))) (and (buffer-modified-p) (not (string-prefix-p " " name)) (or buffer-file-name buffer-offer-save (not (member name (list "*Messages*" "*Warnings*" "*Async-native-compile-log*" "*lsp-log*" "*Lean Goal*" "*Completions*")))))))) (buffer-list))))) (if modified (cons :refused modified) (kill-emacs 0)))' \
        2>/dev/null || true)
      if [[ "$stop_result" == '(:refused '* ]]; then
        printf 'emacs-daemon-restart: refusing to restart; modified buffers: %s\n' "$stop_result" >&2
        exit 1
      fi
      for _attempt in {1..300}; do
        if ! "${emacsClient}" --eval '(emacs-pid)' >/dev/null 2>&1; then
          break
        fi
        ${pkgs.coreutils}/bin/sleep 0.1
      done
      if "${emacsClient}" --eval '(emacs-pid)' >/dev/null 2>&1; then
        printf 'emacs-daemon-restart: old daemon did not stop\n' >&2
        exit 1
      fi

      ${startManagedDaemon}
      ${waitForDaemon}
      if ! wait_for_daemon; then
        printf 'emacs-daemon-restart: replacement daemon did not become ready\n' >&2
        exit 1
      fi
      new_pid=$("${emacsClient}" --eval '(emacs-pid)')
      printf 'old-pid=%s new-pid=%s package=%s\n' "$old_pid" "$new_pid" '${emacsPackage}'
    '';
  };

  emacsClientApp = import ./client-app.nix {
    inherit pkgs emacsFrame emacsPackage;
  };
in
lib.mkMerge [
  {
    services.emacs = {
      enable = isLinux || isDarwin;
      package = emacsPackage;
      defaultEditor = false;
      startWithUserSession = "graphical";
    };

    home.packages = [
      emacsFrame
      emacsDaemonStatus
      emacsDaemonRestart
    ]
    ++ lib.optional isDarwin emacsClientApp;
  }

  (lib.mkIf isDarwin {
    home.file.".local/bin/emacs-daemon".source = "${darwinDaemonShim}/bin/emacs-daemon";

    # Keep the plist stable across Nix generations. Home Manager unloads a
    # launchd agent whenever its plist changes, which is unsafe for an Emacs
    # daemon that may contain unsaved buffers.
    launchd.agents.emacs.config.ProgramArguments = lib.mkForce [
      stableDarwinDaemon
      "--fg-daemon"
    ];
  })
]
