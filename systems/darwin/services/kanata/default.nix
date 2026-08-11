{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkAfter
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.my.services.kanata-macos;

  kanataVersion = "1.12.0";
  driverVersion = "6.2.0";
  driverExtensionVersion = "1.8.0";
  devicePlaceholder = "REPLACE_WITH_EXACT_DEVICE_NAME_FROM_KANATA_LIST";
  bundleIdentifier = "local.kaki.kanata-canary";
  bundleExecutable = "kanata_macos_arm64";
  bundleRevision = "${kanataVersion}-official-arm64-v1";

  driverPackage = (pkgs.karabiner-dk.override { driver-version = driverVersion; }).overrideAttrs (
    _finalAttrs: _previousAttrs: {
      sourceVersion = driverVersion;
      version = driverVersion;
      src = pkgs.fetchFromGitHub {
        owner = "pqrs-org";
        repo = "Karabiner-DriverKit-VirtualHIDDevice";
        tag = "v${driverVersion}";
        hash = "sha256-Gw40F9gB+9sDg8swiOCfpCbc1gNHR0NbISOEJmpkWz8=";
      };
    }
  );

  officialArchive = pkgs.fetchurl {
    url = "https://github.com/jtroo/kanata/releases/download/v${kanataVersion}/macos-binaries-arm64.zip";
    hash = "sha256-g5dp0YmRG1iB4RVQ6qIDlwUhP7clhl0Ij1ouOmwQ3jI=";
  };

  infoPlist = pkgs.writeText "KanataCanary-Info.plist" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDevelopmentRegion</key>
      <string>en</string>
      <key>CFBundleExecutable</key>
      <string>${bundleExecutable}</string>
      <key>CFBundleIdentifier</key>
      <string>${bundleIdentifier}</string>
      <key>CFBundleInfoDictionaryVersion</key>
      <string>6.0</string>
      <key>CFBundleName</key>
      <string>Kanata Canary</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleShortVersionString</key>
      <string>${kanataVersion}</string>
      <key>CFBundleVersion</key>
      <string>${kanataVersion}</string>
      <key>LSBackgroundOnly</key>
      <true/>
    </dict>
    </plist>
  '';

  appBundle =
    pkgs.runCommand "kanata-canary-app-${kanataVersion}"
      {
        nativeBuildInputs = [ pkgs.unzip ];
      }
      ''
        mkdir -p "$out/KanataCanary.app/Contents/MacOS"
        unzip -p ${officialArchive} ${bundleExecutable} > "$out/KanataCanary.app/Contents/MacOS/${bundleExecutable}"
        chmod 0555 "$out/KanataCanary.app/Contents/MacOS/${bundleExecutable}"
        cp ${infoPlist} "$out/KanataCanary.app/Contents/Info.plist"
      '';

  renderedConfig = pkgs.writeText "kanata-macos-shingeta.kbd" (
    builtins.replaceStrings [ devicePlaceholder ] [ cfg.deviceName ] (builtins.readFile ./shingeta.kbd)
  );

  driverSupportPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice";
  driverManagerPath = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app";
  driverDaemonPath = "${driverSupportPath}/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon";
  driverLabel = "org.pqrs.Karabiner-VirtualHIDDevice-Daemon";
  kanataLabel = "local.kaki.kanata-shingeta";

in
{
  options.my.services.kanata-macos = {
    enable = mkEnableOption "the production macOS Kanata LaunchDaemon";

    deviceName = mkOption {
      type = types.str;
      default = devicePlaceholder;
      description = ''
        Exact product name copied from `kanata --list`. The placeholder is
        rejected when the module is enabled so automatic all-keyboard capture
        cannot be selected accidentally.
      '';
    };

    appPath = mkOption {
      type = types.strMatching "^/[A-Za-z0-9._ /-]+[.]app$";
      default = "/Applications/KanataCanary.app";
      description = "Stable, root-controlled real app-bundle path used for TCC and launchd.";
    };

    adoptAppPath = mkOption {
      type = types.nullOr (types.strMatching "^/[A-Za-z0-9._ /-]+[.]app$");
      default = null;
      description = "Previously tested app bundle to copy without re-signing when adoptCDHash matches.";
    };

    adoptCDHash = mkOption {
      type = types.nullOr (types.strMatching "^[0-9a-f]{40}$");
      default = null;
      description = ''
        CDHash of the already-tested app at adoptAppPath. adoptAppPath and
        adoptCDHash must either both be set or both be null. If its bundle
        metadata, version, signature, and CDHash match, activation adopts it
        without re-signing, preserving its existing TCC identity.
      '';
    };

    kanataVersion = mkOption {
      type = types.str;
      readOnly = true;
      default = kanataVersion;
    };

    driverVersion = mkOption {
      type = types.str;
      readOnly = true;
      default = driverVersion;
    };

    driverExtensionVersion = mkOption {
      type = types.str;
      readOnly = true;
      default = driverExtensionVersion;
    };

    driverPackage = mkOption {
      type = types.package;
      readOnly = true;
      default = driverPackage;
      internal = true;
    };

    appBundle = mkOption {
      type = types.package;
      readOnly = true;
      default = appBundle;
      internal = true;
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.kanataVersion == kanataVersion;
        message = "macOS Kanata production is pinned to official Kanata ${kanataVersion}";
      }
      {
        assertion = cfg.driverPackage.version == driverVersion;
        message = "macOS Kanata production is pinned to DriverKit ${driverVersion}";
      }
      {
        assertion = (cfg.adoptAppPath == null) == (cfg.adoptCDHash == null);
        message = "adoptAppPath and adoptCDHash must either both be set or both be null";
      }
      {
        assertion = cfg.deviceName != devicePlaceholder;
        message = "my.services.kanata-macos.deviceName must be an exact name from `kanata --list`";
      }
      {
        assertion = builtins.match ".*[\"\n\r].*" cfg.deviceName == null;
        message = "my.services.kanata-macos.deviceName must not contain quotes or newlines";
      }
      {
        assertion = !config.services.karabiner-elements.enable;
        message = "disable services.karabiner-elements before enabling Kanata; two grabbers must not compete";
      }
    ];

    # These must be real copies. DriverKit will not load its extension from a
    # Nix-store symlink, and Kanata must execute from the stable TCC app path.
    system.activationScripts.applications.text = mkAfter ''
      kanata_app='${cfg.appPath}'
      kanata_marker="${cfg.appPath}.nix-bundle-revision"
      adopt_app='${if cfg.adoptAppPath == null then "" else cfg.adoptAppPath}'
      expected_revision='${bundleRevision}'
      adopt_cdhash='${if cfg.adoptCDHash == null then "" else cfg.adoptCDHash}'
      adopt_existing=false

      validate_kanata_app() {
        candidate="$1"
        expected_cdhash="$2"
        [ -x "$candidate/Contents/MacOS/${bundleExecutable}" ] \
          && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist" 2>/dev/null || true)" = '${bundleIdentifier}' ] \
          && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$candidate/Contents/Info.plist" 2>/dev/null || true)" = '${bundleExecutable}' ] \
          && "$candidate/Contents/MacOS/${bundleExecutable}" --version 2>&1 | /usr/bin/grep -q '${kanataVersion}' \
          && /usr/bin/codesign --verify --deep --strict "$candidate" >/dev/null 2>&1 \
          && { [ -z "$expected_cdhash" ] || /usr/bin/codesign -dvvv "$candidate" 2>&1 | /usr/bin/grep -q "^CDHash=$expected_cdhash$"; }
      }

      install_kanata_app() {
        source_app="$1"
        resign="$2"
        app_parent="$(dirname "$kanata_app")"
        app_stage="$app_parent/.KanataCanary.app.nix-new.$$"
        app_backup="$app_parent/.KanataCanary.app.nix-old.$$"
        mkdir -p "$app_parent"
        rm -rf "$app_stage" "$app_backup"
        /usr/bin/ditto "$source_app" "$app_stage"
        if [ "$resign" = true ]; then
          /usr/bin/codesign --force --deep --sign - --identifier '${bundleIdentifier}' "$app_stage"
        fi
        /usr/bin/codesign --verify --deep --strict "$app_stage"
        /usr/sbin/chown -R root:wheel "$app_stage"
        /usr/bin/find "$app_stage" -type d -exec /bin/chmod 0555 {} +
        /usr/bin/find "$app_stage" -type f -exec /bin/chmod 0444 {} +
        /bin/chmod 0555 "$app_stage/Contents/MacOS/${bundleExecutable}"
        if [ -e "$kanata_app" ]; then mv "$kanata_app" "$app_backup"; fi
        if ! mv "$app_stage" "$kanata_app"; then
          rm -rf "$app_stage" "$kanata_app"
          if [ -e "$app_backup" ]; then mv "$app_backup" "$kanata_app"; fi
          echo "failed to install stable Kanata app; previous app restored" >&2
          exit 1
        fi
        if ! printf '%s\n' "$expected_revision" > "$kanata_marker"; then
          rm -rf "$kanata_app"
          if [ -e "$app_backup" ]; then mv "$app_backup" "$kanata_app"; fi
          echo "failed to record Kanata app revision; previous app restored" >&2
          exit 1
        fi
        /usr/sbin/chown root:wheel "$kanata_marker"
        /bin/chmod 0444 "$kanata_marker"
        rm -rf "$app_backup"
      }

      if [ -f "$kanata_marker" ] \
        && [ "$(cat "$kanata_marker")" = "$expected_revision" ] \
        && validate_kanata_app "$kanata_app" "$adopt_cdhash"; then
        adopt_existing=true
      elif [ -n "$adopt_app" ] \
        && [ -n "$adopt_cdhash" ] \
        && validate_kanata_app "$adopt_app" "$adopt_cdhash"; then
        # Preserve the exact code signature/CDHash that passed the canary while
        # moving it under root-controlled /Applications before root executes it.
        install_kanata_app "$adopt_app" false
        adopt_existing=true
      fi

      if [ "$adopt_existing" != true ]; then
        # Fallback for a missing or mismatched canary app. This deterministic
        # official no-cmd bundle gets a stable identity but may need TCC regrant.
        install_kanata_app '${cfg.appBundle}/KanataCanary.app' true
      fi

      driver_support='${driverSupportPath}'
      driver_manager='${driverManagerPath}'
      support_stage="${driverSupportPath}.nix-new.$$"
      support_backup="${driverSupportPath}.nix-old.$$"
      manager_stage="${driverManagerPath}.nix-new.$$"
      manager_backup="${driverManagerPath}.nix-old.$$"
      rm -rf "$support_stage" "$support_backup" "$manager_stage" "$manager_backup"
      /usr/bin/ditto '${cfg.driverPackage}/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice' "$support_stage"
      /usr/bin/ditto '${cfg.driverPackage}/Applications/.Karabiner-VirtualHIDDevice-Manager.app' "$manager_stage"
      /usr/bin/codesign --verify --deep --strict "$manager_stage"
      /usr/bin/codesign --verify --deep --strict \
        "$support_stage/Applications/Karabiner-VirtualHIDDevice-Daemon.app"

      rollback_driver_files() {
        rm -rf "$driver_support" "$driver_manager"
        if [ -e "$support_backup" ]; then mv "$support_backup" "$driver_support"; fi
        if [ -e "$manager_backup" ]; then mv "$manager_backup" "$driver_manager"; fi
        rm -rf "$support_stage" "$manager_stage"
      }

      if [ -e "$driver_support" ]; then mv "$driver_support" "$support_backup"; fi
      if [ -e "$driver_manager" ]; then mv "$driver_manager" "$manager_backup"; fi
      if ! mv "$support_stage" "$driver_support" || ! mv "$manager_stage" "$driver_manager"; then
        rollback_driver_files
        echo "failed to install DriverKit ${driverVersion} payload; previous files restored" >&2
        exit 1
      fi
      if [ -L "$driver_manager" ] || [ ! -x '${driverDaemonPath}' ]; then
        rollback_driver_files
        echo "DriverKit payload verification failed; previous files restored" >&2
        exit 1
      fi
      rm -rf "$support_backup" "$manager_backup"
    '';

    launchd.daemons.kanata-virtual-hid-daemon.serviceConfig = {
      Label = driverLabel;
      ProgramArguments = [ driverDaemonPath ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive";
      UserName = "root";
      GroupName = "wheel";
      StandardOutPath = "/var/log/kanata-virtual-hid-daemon.log";
      StandardErrorPath = "/var/log/kanata-virtual-hid-daemon.log";
    };

    launchd.daemons.kanata-shingeta.serviceConfig = {
      Label = kanataLabel;
      ProgramArguments = [
        "${cfg.appPath}/Contents/MacOS/${bundleExecutable}"
        "--cfg"
        "${renderedConfig}"
        "--no-wait"
      ];
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      ThrottleInterval = 5;
      ProcessType = "Interactive";
      UserName = "root";
      GroupName = "wheel";
      StandardOutPath = "/var/log/kanata-shingeta.log";
      StandardErrorPath = "/var/log/kanata-shingeta.log";
    };
  };
}
