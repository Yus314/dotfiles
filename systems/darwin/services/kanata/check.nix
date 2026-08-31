{ pkgs, watariConfig }:
let
  lib = pkgs.lib;
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  kanataCfg = watariConfig.my.services.kanata-macos;
  kanataService = watariConfig.launchd.daemons.kanata-shingeta.serviceConfig;
  driverService = watariConfig.launchd.daemons.kanata-virtual-hid-daemon.serviceConfig;
  productionAssertions = [
    {
      assertion = kanataCfg.enable;
      message = "watari must enable the production Kanata module";
    }
    {
      assertion = kanataCfg.kanataVersion == "1.12.0";
      message = "watari official Kanata archive must remain at 1.12.0";
    }
    {
      assertion = kanataCfg.driverPackage.version == "6.2.0";
      message = "watari DriverKit package must remain at 6.2.0";
    }
    {
      assertion = kanataCfg.driverExtensionVersion == "1.8.0";
      message = "DriverKit 6.2.0 must document extension 1.8.0";
    }
    {
      assertion = kanataCfg.deviceName == "Apple Internal Keyboard / Trackpad";
      message = "watari must grab only the tested internal keyboard";
    }
    {
      assertion = kanataCfg.appPath == "/Users/kaki/Applications/KanataCanary.app";
      message = "watari must retain the TCC-tested stable app path";
    }
    {
      assertion =
        kanataCfg.adoptAppPath == kanataCfg.appPath
        && kanataCfg.adoptCDHash == "8c31a4ec989ae59f4317fe7fa0ad78838f433085";
      message = "watari must adopt the exact app and CDHash that passed the real-device canary";
    }
    {
      assertion = !watariConfig.services.karabiner-elements.enable;
      message = "Karabiner-Elements must be disabled on watari";
    }
    {
      assertion = !watariConfig.home-manager.users.kaki.programs.goku.enable;
      message = "Goku must be disabled only in watari's Home Manager profile";
    }
    {
      assertion =
        driverService.ProgramArguments == [
          "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon"
        ];
      message = "the standalone DriverKit daemon must run from its real copied payload";
    }
    {
      assertion = driverService.RunAtLoad && driverService.KeepAlive == true;
      message = "the DriverKit daemon must start at boot and stay alive";
    }
    {
      assertion =
        kanataService.RunAtLoad
        && kanataService.KeepAlive.SuccessfulExit == false
        && kanataService.UserName == "root";
      message = "Kanata must run as root, restart failures, and stay stopped after a successful exit";
    }
    {
      assertion =
        builtins.length kanataService.ProgramArguments == 4
        &&
          builtins.elemAt kanataService.ProgramArguments 0
          == "/Users/kaki/Applications/KanataCanary.app/Contents/MacOS/kanata_macos_arm64"
        && builtins.elemAt kanataService.ProgramArguments 1 == "--cfg"
        &&
          builtins.match "/nix/store/[a-z0-9]+-kanata-macos-shingeta[.]kbd" (
            builtins.elemAt kanataService.ProgramArguments 2
          ) != null
        && builtins.elemAt kanataService.ProgramArguments 3 == "--no-wait";
      message = "Kanata launchd must directly execute the TCC-bound app with only cfg/no-wait arguments";
    }
  ];
  productionAssertionsPass = lib.all (
    item: lib.assertMsg item.assertion item.message
  ) productionAssertions;
  parserPreparation =
    if pkgs.stdenv.isDarwin then
      "cp generated.kbd parser.kbd"
    else
      ''
        python -c '
        from pathlib import Path
        path = Path("generated.kbd")
        lines = path.read_text().splitlines(keepends=True)
        start = lines.index("  macos-dev-names-include (\n")
        assert lines[start + 1].strip() == chr(34) + "REPLACE_WITH_EXACT_DEVICE_NAME_FROM_KANATA_LIST" + chr(34)
        assert lines[start + 2] == "  )\n"
        lines[start : start + 3] = ["  linux-continue-if-no-devs-found yes\n"]
        Path("parser.kbd").write_text("".join(lines))
        '
      '';
  parserExecutable =
    if pkgs.stdenv.isDarwin then
      "${kanataCfg.appBundle}/KanataCanary.app/Contents/MacOS/kanata_macos_arm64"
    else
      "kanata";
  parserInputs = [
    python
    pkgs.diffutils
  ]
  ++ lib.optional (!pkgs.stdenv.isDarwin) pkgs.kanata;
in
assert productionAssertionsPass;
pkgs.runCommand "shingeta-kanata-macos-check"
  {
    nativeBuildInputs = parserInputs;
  }
  ''
    SHINGETA_GENERATOR=${../../../nixos/services/kanata/generate_shingeta.py} \
      SHINGETA_SOURCE=${../../../nixos/services/xremap/shingeta.yml} \
      SHINGETA_MAC_GENERATED=${./shingeta.kbd} \
      AQUASKK_KEYMAP=${../../../../homes/darwin/keymap.conf} \
      python ${./test_generate_shingeta.py}

    python ${../../../nixos/services/kanata/generate_shingeta.py} \
      --platform macos \
      --source ${../../../nixos/services/xremap/shingeta.yml} \
      --output generated.kbd

    if ! cmp -s generated.kbd ${./shingeta.kbd}; then
      echo "generated macOS Kanata config differs from committed shingeta.kbd" >&2
      diff -u ${./shingeta.kbd} generated.kbd >&2 || true
      exit 1
    fi

    ${parserPreparation}
    ${parserExecutable} --cfg parser.kbd --check
    touch "$out"
  ''
