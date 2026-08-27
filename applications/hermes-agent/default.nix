# Hermes Agent — always-on messaging gateway (Discord), run as a home-manager
# user service so the Codex (ChatGPT) OAuth login lives in your own ~/.hermes.
#
# Pinned to the qualified upstream v0.19.0 release. Keep Hermes' own flake
# inputs rather than forcing the workstation nixpkgs into its uv2nix build.
#
# One-time interactive setup (run as your user, on this host):
#   hermes model      # choose "OpenAI Codex" -> device-code login (ChatGPT
#                     #   Plus) -> set default model to gpt-5.6-sol
#   hermes fallback add openrouter/anthropic/claude-sonnet-4   # optional fallback
#   systemctl --user restart hermes-gateway
#
# Secret env (sops):  sops applications/hermes-agent/secrets.yaml
#   env: |
#     OPENROUTER_API_KEY=sk-or-...
#     DISCORD_BOT_TOKEN=...
#     DISCORD_CAREER_BOT_TOKEN=...
#     DISCORD_ENGLISH_BOT_TOKEN=...
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  honchoAi = pkgs.python312Packages.buildPythonPackage rec {
    pname = "honcho-ai";
    version = "2.0.1";
    pyproject = true;

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/93/30/d30ba159404050d53b4b1b1c4477f9591f43af18758be1fb7dab6afbfe7d/honcho_ai-${version}.tar.gz";
      hash = "sha256-b97r+UVOYrxSPVeIjlA1nme6r9sh9oYh+cFOCNwAYjo=";
    };

    build-system = [ pkgs.python312Packages.setuptools ];
    dependencies = with pkgs.python312Packages; [
      httpx
      pydantic
    ];

    pythonImportsCheck = [ "honcho" ];
  };

  # W50 production-SHADOW diagnostics: layer the reviewed reply/message
  # batching-boundary repair after the existing exact W40 composition.
  w40HermesPlane =
    assert inputs.hermes-agent.packages.${pkgs.system}.messaging.version == "0.19.0";
    pkgs.runCommand "hermes-agent-w50-shadow-0.19.0" { nativeBuildInputs = [ pkgs.patch ]; } ''
      cp -R ${inputs.hermes-agent} "$out"
      chmod -R u+w "$out"

      test "$(sha256sum "$out/gateway/run.py" | cut -d' ' -f1)" = c6e0f443772e4a8a7eac0d9ccf9a4f659de5fc5493c572a69a46e4c61a8aa966
      test "$(sha256sum "$out/agent/turn_context.py" | cut -d' ' -f1)" = fa273c7496c4e06a8c1834f835acdf8b0b12e7302d9ed9048118f4a3f442178d
      test "$(sha256sum "$out/plugins/platforms/discord/adapter.py" | cut -d' ' -f1)" = 84b0f4912d6661ab57b102bb6d0509206b6383ba1384feae80b5894d320466d7
      test "$(sha256sum ${./patches/w40-composed-hermes.patch} | cut -d' ' -f1)" = 7f7f1b6ebeda471be511030c8e90c2cd5be54deef7bba2eec103e9e8e9ddf027

      mkdir -p "$out/.w40-baseline/gateway" "$out/.w40-baseline/agent" \
        "$out/.w40-baseline/plugins/platforms/discord"
      cp "$out/gateway/run.py" "$out/.w40-baseline/gateway/run.py"
      cp "$out/agent/turn_context.py" "$out/.w40-baseline/agent/turn_context.py"
      cp "$out/plugins/platforms/discord/adapter.py" \
        "$out/.w40-baseline/plugins/platforms/discord/adapter.py"

      patch --fuzz=0 -p1 -d "$out" < ${./patches/w40-composed-hermes.patch}
      test "$(sha256sum "$out/gateway/run.py" | cut -d' ' -f1)" = b816475affba3ae946ffb8dd365d7da8b29a1b877148d331abdf5b16a4e4e425
      test "$(sha256sum "$out/agent/turn_context.py" | cut -d' ' -f1)" = 5752abc7ec12966a1ef4a6f77e3cbba8f9dcfec78f161f6268d4e06c244cb02e
      test "$(sha256sum "$out/plugins/platforms/discord/adapter.py" | cut -d' ' -f1)" = f8fd891c9e9c47d02ed84b360e5bff5690b998afeb942ce6ccf6de681e8d3dcd

      patch --fuzz=0 -p1 -d "$out/plugins" < ${./discord-skip-empty-messages.patch}
      test "$(sha256sum "$out/plugins/platforms/discord/adapter.py" | cut -d' ' -f1)" = 91d34ac557e735103393534c6bc066f9fc6e1bc8d1767d6c9842ad0620e04b38

      test "$(sha256sum ${./patches/w50-hermes-reply-batch-boundary.patch} | cut -d' ' -f1)" = 583b0a57c422b6822922c8121da8d772566c18fd3404e2bd1989a8e1a850f35d
      patch --fuzz=0 -p1 -d "$out" < ${./patches/w50-hermes-reply-batch-boundary.patch}
      test "$(sha256sum "$out/plugins/platforms/discord/adapter.py" | cut -d' ' -f1)" = c2ce0a2dcf645e19bf7c4bf3de341c2cc18da93fe290783f940b589f6c667713

      test "$(sha256sum ${./plugins/natural-ok-unified-shadow/__init__.py} | cut -d' ' -f1)" = 9e3299c64984446a0c938369fdaa069d3258c2e3cf07737b2a23ad402f0df221
      test "$(sha256sum ${./plugins/natural-ok-unified-shadow/core/state.py} | cut -d' ' -f1)" = 455336733e0494f4be524cede77fa8ab997f05e9ea4e062afb4c90b31d2fa91d
      cp -R ${./plugins/natural-ok-unified-shadow} \
        "$out/plugins/natural-ok-unified-shadow"
      test "$(sha256sum "$out/plugins/natural-ok-unified-shadow/__init__.py" | cut -d' ' -f1)" = 9e3299c64984446a0c938369fdaa069d3258c2e3cf07737b2a23ad402f0df221
      test "$(sha256sum "$out/plugins/natural-ok-unified-shadow/core/state.py" | cut -d' ' -f1)" = 455336733e0494f4be524cede77fa8ab997f05e9ea4e062afb4c90b31d2fa91d
    '';

  hermesPlugins = pkgs.runCommand "hermes-agent-plugins-0.19.0-w50-shadow" { } ''
    cp -R ${w40HermesPlane}/plugins "$out"
    chmod -R u+w "$out"
    cp -R ${./plugins/context_engine/phase_checkpoint} "$out/phase_checkpoint"
  '';

  hermes = inputs.hermes-agent.packages.${pkgs.system}.messaging.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      test -L "$out/share/hermes-agent/plugins"
      rm "$out/share/hermes-agent/plugins"
      ln -s ${hermesPlugins} "$out/share/hermes-agent/plugins"

      for executable in hermes hermes-agent hermes-acp; do
        wrapProgram "$out/bin/$executable" \
          --set PYTHONPATH "${w40HermesPlane}:${honchoAi}/${pkgs.python312.sitePackages}" \
          --set HERMES_LAZY_INSTALL_TARGET ${lib.escapeShellArg hermesLazyInstallTarget}
      done
    '';
  });

  # agent-browser ships prebuilt native binaries in the npm tarball. Package it
  # directly instead of relying on `npx agent-browser`: Hermes' bundled Node can
  # point at a broken/empty npx shim under Nix, which makes browser_navigate fail
  # with Exec format errors. autoPatchelf makes the upstream Linux binary run on
  # NixOS.
  agentBrowser = pkgs.stdenv.mkDerivation rec {
    pname = "agent-browser";
    version = "0.27.3";

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/agent-browser/-/agent-browser-${version}.tgz";
      hash = "sha256-cy+EFjY5F/JpbvMYlyxHm3nKd4yy0uXCKUlS34a6ylk=";
    };

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.makeWrapper
    ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];

    unpackPhase = ''
      tar -xzf $src
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/agent-browser $out/bin
      cp -R package/* $out/lib/agent-browser/
      chmod +x $out/lib/agent-browser/bin/agent-browser-linux-x64
      makeWrapper $out/lib/agent-browser/bin/agent-browser-linux-x64 $out/bin/agent-browser
      runHook postInstall
    '';
  };

  computerUseLinuxRaw = pkgs.callPackage ../../pkgs/computer-use-linux { };
  computerUseLinux = pkgs.writeShellApplication {
    name = "computer-use-linux";
    runtimeInputs = [
      computerUseLinuxRaw
      pkgs.coreutils
      pkgs.glib
      pkgs.procps
      pkgs.systemd
    ];
    text = ''
      # A gateway may predate the Niri login. Import only the graphical keys
      # required by the desktop client instead of inheriting the manager's full
      # environment (which can contain credentials).
      while IFS='=' read -r key value; do
        case "$key" in
          WAYLAND_DISPLAY|NIRI_SOCKET|DISPLAY|XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP|DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR)
            declare -gx "$key=$value"
            ;;
        esac
      done < <(systemctl --user show-environment)

      export XDG_DATA_DIRS=${pkgs.at-spi2-core}/share:"''${XDG_DATA_DIRS:-/run/current-system/sw/share}"
      exec ${computerUseLinuxRaw}/bin/computer-use-linux "$@"
    '';
  };

  computerUseSyntheticTargetRaw = pkgs.stdenv.mkDerivation {
    pname = "hermes-computer-use-synthetic-target";
    version = "1";
    src = ./computer-use-pilot/synthetic-target.c;
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [
      pkgs.at-spi2-core
      pkgs.gtk3
    ];
    buildPhase = ''
      runHook preBuild
      $CC $NIX_CFLAGS_COMPILE -Wall -Wextra -Werror \
        $(pkg-config --cflags gtk+-3.0 atk-bridge-2.0) \
        "$src" -o hermes-computer-use-synthetic-target \
        $(pkg-config --libs gtk+-3.0 atk-bridge-2.0)
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 hermes-computer-use-synthetic-target \
        $out/bin/hermes-computer-use-synthetic-target
      runHook postInstall
    '';
  };
  computerUseSyntheticTarget = pkgs.writeShellApplication {
    name = "hermes-computer-use-synthetic-target";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      while IFS='=' read -r key value; do
        case "$key" in
          WAYLAND_DISPLAY|DISPLAY|DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR)
            declare -gx "$key=$value"
            ;;
        esac
      done < <(systemctl --user show-environment)
      unset NO_AT_BRIDGE
      export GTK_A11Y=atspi
      exec ${computerUseSyntheticTargetRaw}/bin/hermes-computer-use-synthetic-target "$@"
    '';
  };
  computerUseReadonlyBroker = pkgs.writeShellApplication {
    name = "hermes-computer-use-readonly";
    runtimeInputs = [ hermesConfigPython ];
    text = ''
      exec ${hermesConfigPython}/bin/python \
        ${./computer-use-pilot/readonly_broker.py} \
        --computer-use ${computerUseLinux}/bin/computer-use-linux \
        --target-executable ${computerUseSyntheticTargetRaw}/bin/hermes-computer-use-synthetic-target
    '';
  };

  # Your Discord user id — only this account may talk to the bot.
  discordUserId = "885083579367972874";

  gatewayPath = "${agentBrowser}/bin:${pkgs.nodejs_24}/bin:%h/.nix-profile/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin";
  healthGoogleEnvFile = config.sops.secrets."hermes-health-google-env".path;
  # Hermes' Python environment is immutable under Nix. Redirect its pinned,
  # allowlisted optional SDK installs to a durable append-only user directory
  # instead of attempting ensurepip inside /nix/store.
  hermesLazyInstallTarget = "${config.xdg.dataHome}/hermes/lazy-packages";
  hermesConfigPython = pkgs.python312.withPackages (ps: [ ps.pyyaml ]);
  gatewayPreflight = ./scripts/gateway_preflight.py;
  gatewayChannelsConfig = ./scripts/gateway_channels_config.py;
  researchConfig = ./scripts/research_config.py;
  phaseContextConfig = ./scripts/phase_context_config.py;
  desktopNotificationConfig = ./scripts/desktop_notification_config.py;
  computerUseConfig = ./scripts/computer_use_config.py;
  naturalOkShadowConfig = ./scripts/natural_ok_shadow_config.py;
  naturalOkShadowPreflight = ./scripts/natural_ok_shadow_preflight.py;
  naturalOkShadowStateRoot = "${config.xdg.stateHome}/hermes-natural-ok-shadow";
  naturalOkShadowVersionFile = pkgs.writeText "hermes-w40-version" "0.19.0\n";
  # Values belong in the existing SOPS-backed hermes-gateway-env. All five are
  # mandatory together. Optional scope values use literal `null`; empty is invalid.
  naturalOkShadowSecretNames = [
    "HERMES_NATURAL_OK_OWNER_ACTOR_SHA256"
    "HERMES_NATURAL_OK_SCOPE_CHAT_ID"
    "HERMES_NATURAL_OK_SCOPE_THREAD_ID"
    "HERMES_NATURAL_OK_SCOPE_GUILD_ID"
    "HERMES_NATURAL_OK_SCOPE_PARENT_CHAT_ID"
  ];

  gatewayChannels = {
    default = "1515982177454653582";
    food = "1516615713828110426";
    finance = "1516728002904588408";
    math = "1516742897737928814";
    health = "1516773877156679731";
    career = "1523324848237973575";
    english = "1523329905389994094";
    indiedev = "1525076018044473434";
    economics = "1526234512877551636";
  };
  discordTokenVariables = [
    "DISCORD_BOT_TOKEN"
    "DISCORD_FOOD"
    "DISCORD_FINANCE_BOT_TOKEN"
    "DISCORD_MATH_BOT_TOKEN"
    "DISCORD_HEALTH_BOT_TOKEN"
    "DISCORD_CAREER_BOT_TOKEN"
    "DISCORD_ENGLISH_BOT_TOKEN"
    "DISCORD_INDIEDEV_BOT_TOKEN"
    "DISCORD_ECONOMICS_BOT_TOKEN"
  ];
  mkGatewayRunner =
    {
      profile,
      tokenVariable,
    }:
    let
      isDefault = profile == "default";
      profileFlag = lib.optionalString (!isDefault) "--profile ${profile} ";
      configRelativePath =
        if isDefault then ".hermes/config.yaml" else ".hermes/profiles/${profile}/config.yaml";
    in
    pkgs.writeShellScript "hermes-${profile}-gateway" ''
      set -eu
      token_variable=${lib.escapeShellArg tokenVariable}
      token="''${!token_variable-}"
      : "''${token:?${tokenVariable} must be set in hermes-gateway-env}"
      unset ${lib.concatStringsSep " " discordTokenVariables}
      unset DISCORD_ALLOWED_USERS DISCORD_ALLOWED_CHANNELS DISCORD_ALLOW_ALL_USERS
      unset DISCORD_ALLOWED_ROLES DISCORD_DM_ROLE_AUTH_GUILD DISCORD_ALLOW_BOTS
      unset GATEWAY_ALLOWED_USERS GATEWAY_ALLOW_ALL_USERS
      export DISCORD_BOT_TOKEN="$token"
      export DISCORD_ALLOWED_USERS=${lib.escapeShellArg discordUserId}
      export DISCORD_ALLOWED_CHANNELS=${lib.escapeShellArg gatewayChannels.${profile}}
      export DISCORD_ALLOW_ALL_USERS=false
      export DISCORD_ALLOWED_ROLES=""
      export DISCORD_DM_ROLE_AUTH_GUILD=""
      export DISCORD_ALLOW_BOTS=false
      export GATEWAY_ALLOW_ALL_USERS=false
      unset token token_variable

      config_path="$HOME/${configRelativePath}"
      ${hermesConfigPython}/bin/python ${gatewayPreflight} "$config_path" ${
        lib.escapeShellArg gatewayChannels.${profile}
      }
      unset config_path

      exec ${hermes}/bin/hermes ${profileFlag}gateway run
    '';

  defaultGatewayRunner = mkGatewayRunner {
    profile = "default";
    tokenVariable = "DISCORD_BOT_TOKEN";
  };
  naturalOkShadowGatewayRunner = pkgs.writeShellScript "hermes-default-w50-shadow-gateway" ''
    set -eu
    # Force all five names to be dereferenced without printing their values.
    for variable in ${lib.concatStringsSep " " naturalOkShadowSecretNames}; do
      test -n "''${!variable-}" || {
        printf '%s\n' "W50 production-SHADOW: missing required environment name" >&2
        exit 1
      }
    done
    ${hermesConfigPython}/bin/python ${naturalOkShadowPreflight} \
      --config "$HOME/.hermes/config.yaml" \
      --state-root ${lib.escapeShellArg naturalOkShadowStateRoot} \
      --version-file ${naturalOkShadowVersionFile} \
      --baseline-root ${w40HermesPlane}/.w40-baseline \
      --patched-root ${w40HermesPlane} \
      --patch ${./patches/w40-composed-hermes.patch} \
      --w50-patch ${./patches/w50-hermes-reply-batch-boundary.patch}
    exec ${defaultGatewayRunner}
  '';
  foodGatewayRunner = mkGatewayRunner {
    profile = "food";
    tokenVariable = "DISCORD_FOOD";
  };
  financeGatewayRunner = mkGatewayRunner {
    profile = "finance";
    tokenVariable = "DISCORD_FINANCE_BOT_TOKEN";
  };
  mathGatewayRunner = mkGatewayRunner {
    profile = "math";
    tokenVariable = "DISCORD_MATH_BOT_TOKEN";
  };
  healthGatewayRunner = mkGatewayRunner {
    profile = "health";
    tokenVariable = "DISCORD_HEALTH_BOT_TOKEN";
  };
  careerGatewayRunner = mkGatewayRunner {
    profile = "career";
    tokenVariable = "DISCORD_CAREER_BOT_TOKEN";
  };
  englishGatewayRunner = mkGatewayRunner {
    profile = "english";
    tokenVariable = "DISCORD_ENGLISH_BOT_TOKEN";
  };
  indiedevGatewayRunner = mkGatewayRunner {
    profile = "indiedev";
    tokenVariable = "DISCORD_INDIEDEV_BOT_TOKEN";
  };
  economicsGatewayRunner = mkGatewayRunner {
    profile = "economics";
    tokenVariable = "DISCORD_ECONOMICS_BOT_TOKEN";
  };

  modusVivendiSkin = ''
    name: modus-vivendi
    description: Modus Vivendi inspired high-contrast dark theme
    colors:
      banner_border: "#2fafff"
      banner_title: "#ffffff"
      banner_accent: "#00d3d0"
      banner_dim: "#989898"
      banner_text: "#ffffff"
      ui_accent: "#2fafff"
      ui_label: "#00d3d0"
      ui_ok: "#44bc44"
      ui_error: "#ff5f59"
      ui_warn: "#d0bc00"
      prompt: "#ffffff"
      input_rule: "#2fafff"
      response_border: "#2fafff"
      status_bar_bg: "#110b11"
      status_bar_text: "#ffffff"
      status_bar_strong: "#2fafff"
      status_bar_dim: "#989898"
      status_bar_good: "#44bc44"
      status_bar_warn: "#d0bc00"
      status_bar_bad: "#ff9f80"
      status_bar_critical: "#ff5f59"
      session_label: "#00d3d0"
      session_border: "#989898"
      selection_bg: "#10387c"
      completion_menu_bg: "#000000"
      completion_menu_current_bg: "#10387c"
      completion_menu_meta_bg: "#110b11"
      completion_menu_meta_current_bg: "#2a40b8"
    spinner: {}
    branding:
      agent_name: "Hermes Agent"
      welcome: "Welcome to Hermes Agent! Type your message or /help for commands."
      goodbye: "Goodbye! ⚕"
      response_label: " ⚕ Hermes "
      prompt_symbol: "❯"
      help_header: "[?] Available Commands"
    tool_prefix: "│"
  '';

  modusOperandiSkin = ''
    name: modus-operandi
    description: Modus Operandi inspired high-contrast light theme
    colors:
      banner_border: "#0031a9"
      banner_title: "#000000"
      banner_accent: "#005e8b"
      banner_dim: "#595959"
      banner_text: "#000000"
      ui_accent: "#0031a9"
      ui_label: "#005e8b"
      ui_ok: "#006800"
      ui_error: "#a60000"
      ui_warn: "#6f5500"
      prompt: "#000000"
      input_rule: "#0031a9"
      response_border: "#0031a9"
      status_bar_bg: "#f2f2f2"
      status_bar_text: "#000000"
      status_bar_strong: "#0031a9"
      status_bar_dim: "#595959"
      status_bar_good: "#006800"
      status_bar_warn: "#6f5500"
      status_bar_bad: "#8f0075"
      status_bar_critical: "#a60000"
      session_label: "#005e8b"
      session_border: "#595959"
      selection_bg: "#c2dbff"
      completion_menu_bg: "#ffffff"
      completion_menu_current_bg: "#c2dbff"
      completion_menu_meta_bg: "#f2f2f2"
      completion_menu_meta_current_bg: "#d5e5ff"
    spinner: {}
    branding:
      agent_name: "Hermes Agent"
      welcome: "Welcome to Hermes Agent! Type your message or /help for commands."
      goodbye: "Goodbye! ⚕"
      response_label: " ⚕ Hermes "
      prompt_symbol: "❯"
      help_header: "[?] Available Commands"
    tool_prefix: "│"
  '';
in
{
  imports = [
    ./shared-workflows.nix
    ./usage-adapters.nix
  ];

  config = lib.mkMerge [
    {
      # The math profile reads its own .env through Hermes' profile-aware
      # HERMES_HOME resolution. sops-nix decrypts at activation time; neither
      # the value nor a derived fingerprint enters Nix evaluation or the store.
      sops.secrets."hermes-math-env" = {
        sopsFile = ./secrets.yaml;
        key = "math_honcho_env";
        path = "${config.home.homeDirectory}/.hermes/profiles/math/.env";
        mode = "0400";
      };

      home.packages = [
        hermes
        pkgs.nodejs_24
        pkgs.uv
      ];

      home.file = {
        ".hermes/mcp/research_providers_server.py".source = ./research_providers_server.py;
        ".hermes/skins/modus-vivendi.yaml".text = modusVivendiSkin;
        ".hermes/skins/modus-operandi.yaml".text = modusOperandiSkin;
      };

      home.activation.hermesLazyInstallTarget = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -d -m 0700 \
          ${lib.escapeShellArg hermesLazyInstallTarget}
      '';

      home.activation.hermesResearchProvidersConfig =
        lib.hm.dag.entryAfter [ "hermesLazyInstallTarget" ]
          ''
            $DRY_RUN_CMD ${hermesConfigPython}/bin/python ${researchConfig} "$HOME/.hermes/config.yaml"
          '';

      home.activation.hermesPhaseContextConfig =
        lib.hm.dag.entryAfter [ "hermesResearchProvidersConfig" ]
          ''
            $DRY_RUN_CMD ${hermesConfigPython}/bin/python ${phaseContextConfig} "$HOME/.hermes/config.yaml"
          '';

      home.activation.hermesDesktopNotificationConfig =
        lib.hm.dag.entryAfter [ "hermesPhaseContextConfig" ]
          ''
            $DRY_RUN_CMD ${hermesConfigPython}/bin/python ${desktopNotificationConfig} "$HOME/.hermes/config.yaml"
          '';
    }

    (lib.mkIf pkgs.stdenv.isLinux {
      sops.secrets."hermes-gateway-env" = {
        sopsFile = ./secrets.yaml;
        key = "env";
        mode = "0400";
      };

      sops.secrets."hermes-health-google-env" = {
        sopsFile = ./secrets.yaml;
        key = "health_google_env";
        mode = "0400";
      };

      home.packages = [
        agentBrowser
        computerUseReadonlyBroker
        computerUseSyntheticTarget
      ];

      home.activation.hermesComputerUseConfig =
        lib.hm.dag.entryAfter [ "hermesDesktopNotificationConfig" ]
          ''
            $DRY_RUN_CMD ${hermesConfigPython}/bin/python ${computerUseConfig} \
              "$HOME/.hermes/config.yaml" ${computerUseReadonlyBroker}/bin/hermes-computer-use-readonly
          '';

      home.activation.hermesNaturalOkShadowConfig = lib.hm.dag.entryAfter [ "hermesComputerUseConfig" ] ''
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -d -m 0700 \
          ${lib.escapeShellArg naturalOkShadowStateRoot}
        $DRY_RUN_CMD ${hermesConfigPython}/bin/python ${naturalOkShadowConfig} \
          --enable "$HOME/.hermes/config.yaml"
      '';

      home.activation.hermesGatewayChannels =
        lib.hm.dag.entryAfter
          [
            "writeBoundary"
            "hermesComputerUseConfig"
            "hermesNaturalOkShadowConfig"
          ]
          ''
            $DRY_RUN_CMD ${hermesConfigPython}/bin/python ${gatewayChannelsConfig} ${lib.escapeShellArg (builtins.toJSON gatewayChannels)}
          '';

      systemd.user.services.hermes-computer-use-atspi = {
        Unit = {
          Description = "AT-SPI bus for the Hermes computer-use read-only pilot";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.at-spi2-core}/libexec/at-spi-bus-launcher --launch-immediately --a11y=1 --screen-reader=0";
          Restart = "on-failure";
          RestartSec = "2s";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      systemd.user.services.hermes-gateway = {
        Unit = {
          Description = "Hermes Agent messaging gateway (Discord)";
          # Deployment and restart are separate gates for W47. Home Manager may
          # install the new unit, but must not restart the live gateway implicitly.
          X-RestartIfChanged = false;
          After = [
            "network-online.target"
            "sops-nix.service"
          ];
          Wants = [ "network-online.target" ];
        };

        Service = {
          Environment = [
            "HERMES_HOME=%h/.hermes"
            "HERMES_NATURAL_OK_STATE_ROOT=${naturalOkShadowStateRoot}"
            "HERMES_NATURAL_OK_TIMEDATECTL=${pkgs.systemd}/bin/timedatectl"
            "DISCORD_ALLOWED_USERS=${discordUserId}"
            "DISCORD_REQUIRE_MENTION=false"
            "PATH=${gatewayPath}"
          ];
          # The W47 wrapper performs the value-hidden exact-version/hash/config
          # preflight before delegating to the existing default runner.
          EnvironmentFile = config.sops.secrets."hermes-gateway-env".path;
          ExecStart = "${naturalOkShadowGatewayRunner}";
          # Retries until the one-time `hermes model` (Codex auth) has populated
          # ~/.hermes (auth.json + config.yaml).
          Restart = "always";
          RestartSec = "10";
          # v0.19 defaults restart_drain_timeout to 0 so shutdown can interrupt,
          # persist delivery obligations, clean up, and exit without a SIGKILL.
          TimeoutStopSec = "210s";
        };

        Install.WantedBy = [ "default.target" ];
      };

      systemd.user.services.hermes-food-gateway = {
        Unit = {
          Description = "Hermes Agent food messaging gateway (Discord)";
          After = [
            "network-online.target"
            "sops-nix.service"
          ];
          Wants = [ "network-online.target" ];
        };

        Service = {
          Environment = [
            "HERMES_HOME=%h/.hermes"
            "DISCORD_ALLOWED_USERS=${discordUserId}"
            "DISCORD_REQUIRE_MENTION=false"
            "PATH=${gatewayPath}"
          ];
          # DISCORD_FOOD is the food bot token. The wrapper maps it to the
          # DISCORD_BOT_TOKEN name consumed by Hermes' Discord adapter.
          EnvironmentFile = config.sops.secrets."hermes-gateway-env".path;
          ExecStart = "${foodGatewayRunner}";
          Restart = "always";
          RestartSec = "10";
          TimeoutStopSec = "210s";
        };

        Install.WantedBy = [ "default.target" ];
      };

      systemd.user.services.hermes-finance-gateway = {
        Unit = {
          Description = "Hermes Agent finance messaging gateway (Discord)";
          After = [
            "network-online.target"
            "sops-nix.service"
          ];
          Wants = [ "network-online.target" ];
        };

        Service = {
          Environment = [
            "HERMES_HOME=%h/.hermes"
            "DISCORD_ALLOWED_USERS=${discordUserId}"
            # Finance bot is isolated to its own Discord finance surface, so it may
            # respond without explicit mentions there.
            "DISCORD_REQUIRE_MENTION=false"
            "PATH=${gatewayPath}"
          ];
          # DISCORD_FINANCE_BOT_TOKEN is the finance bot token. The wrapper maps it to the
          # DISCORD_BOT_TOKEN name consumed by Hermes' Discord adapter.
          EnvironmentFile = config.sops.secrets."hermes-gateway-env".path;
          ExecStart = "${financeGatewayRunner}";
          Restart = "always";
          RestartSec = "10";
          TimeoutStopSec = "210s";
        };

        Install.WantedBy = [ "default.target" ];
      };

      systemd.user.services.hermes-math-gateway = {
        Unit = {
          Description = "Hermes Agent math messaging gateway (Discord)";
          After = [
            "network-online.target"
            "sops-nix.service"
          ];
          Wants = [ "network-online.target" ];
        };

        Service = {
          Environment = [
            "HERMES_HOME=%h/.hermes"
            "DISCORD_ALLOWED_USERS=${discordUserId}"
            # Math bot is isolated to its intended Discord channel/thread, so it may
            # respond without explicit mentions there.
            "DISCORD_REQUIRE_MENTION=false"
            "PATH=${gatewayPath}"
          ];
          # DISCORD_MATH_BOT_TOKEN is the math bot token. The wrapper maps it to the
          # DISCORD_BOT_TOKEN name consumed by Hermes' Discord adapter.
          EnvironmentFile = config.sops.secrets."hermes-gateway-env".path;
          ExecStart = "${mathGatewayRunner}";
          Restart = "always";
          RestartSec = "10";
          TimeoutStopSec = "210s";
        };

        Install.WantedBy = [ "default.target" ];
      };

      systemd.user.services.hermes-career-gateway = {
        Unit = {
          Description = "Hermes Agent career advisor messaging gateway (Discord)";
          After = [
            "network-online.target"
            "sops-nix.service"
          ];
          Wants = [ "network-online.target" ];
        };

        Service = {
          Environment = [
            "HERMES_HOME=%h/.hermes"
            "DISCORD_ALLOWED_USERS=${discordUserId}"
            # Career advice can include private employment, compensation, and CV
            # details. Scope the bot with the career profile's
            # discord.allowed_channels setting, matching the other profile gateways.
            "DISCORD_REQUIRE_MENTION=false"
            "PATH=${gatewayPath}"
          ];
          # DISCORD_CAREER_BOT_TOKEN is the career bot token. The wrapper maps it to
          # the DISCORD_BOT_TOKEN name consumed by Hermes' Discord adapter.
          EnvironmentFile = config.sops.secrets."hermes-gateway-env".path;
          ExecStart = "${careerGatewayRunner}";
          Restart = "always";
          RestartSec = "10";
          TimeoutStopSec = "210s";
        };

        Install.WantedBy = [ "default.target" ];
      };

      systemd.user.services.hermes-english-gateway = {
        Unit = {
          Description = "Hermes Agent English learning messaging gateway (Discord)";
          After = [
            "network-online.target"
            "sops-nix.service"
          ];
          Wants = [ "network-online.target" ];
        };

        Service = {
          Environment = [
            "HERMES_HOME=%h/.hermes"
            "DISCORD_ALLOWED_USERS=${discordUserId}"
            # The English bot is scoped by the english profile's
            # discord.allowed_channels setting and can respond without mentions in
            # that dedicated learning channel.
            "DISCORD_REQUIRE_MENTION=false"
            "PATH=${gatewayPath}"
          ];
          # DISCORD_ENGLISH_BOT_TOKEN is the English bot token. The wrapper maps it
          # to the DISCORD_BOT_TOKEN name consumed by Hermes' Discord adapter.
          EnvironmentFile = config.sops.secrets."hermes-gateway-env".path;
          ExecStart = "${englishGatewayRunner}";
          Restart = "always";
          RestartSec = "10";
          TimeoutStopSec = "210s";
        };

        Install.WantedBy = [ "default.target" ];
      };

      systemd.user.services.hermes-indiedev-gateway = {
        Unit = {
          Description = "Hermes Agent indie development messaging gateway (Discord)";
          After = [
            "network-online.target"
            "sops-nix.service"
          ];
          Wants = [ "network-online.target" ];
        };

        Service = {
          Environment = [
            "HERMES_HOME=%h/.hermes"
            "DISCORD_ALLOWED_USERS=${discordUserId}"
            # The indiedev bot is scoped by the indiedev profile's
            # discord.allowed_channels setting and can respond without mentions in
            # that dedicated product-development channel. Hermes' Discord adapter
            # still auto-threads free-response channel messages; use
            # discord.no_thread_channels for direct-reply exceptions.
            "DISCORD_REQUIRE_MENTION=false"
            "PATH=${gatewayPath}"
          ];
          # DISCORD_INDIEDEV_BOT_TOKEN is the indiedev bot token. The wrapper maps
          # it to the DISCORD_BOT_TOKEN name consumed by Hermes' Discord adapter.
          EnvironmentFile = config.sops.secrets."hermes-gateway-env".path;
          ExecStart = "${indiedevGatewayRunner}";
          Restart = "always";
          RestartSec = "10";
          TimeoutStopSec = "210s";
        };

        Install.WantedBy = [ "default.target" ];
      };

      systemd.user.services.hermes-economics-gateway = {
        Unit = {
          Description = "Hermes Agent economics learning messaging gateway (Discord)";
          After = [
            "network-online.target"
            "sops-nix.service"
          ];
          Wants = [ "network-online.target" ];
        };

        Service = {
          Environment = [
            "HERMES_HOME=%h/.hermes"
            "DISCORD_ALLOWED_USERS=${discordUserId}"
            # The economics bot is scoped by the economics profile's
            # discord.allowed_channels setting and can respond without mentions in
            # that dedicated learning channel.
            "DISCORD_REQUIRE_MENTION=false"
            "PATH=${gatewayPath}"
          ];
          # DISCORD_ECONOMICS_BOT_TOKEN is the economics bot token. The wrapper maps
          # it to the DISCORD_BOT_TOKEN name consumed by Hermes' Discord adapter.
          EnvironmentFile = config.sops.secrets."hermes-gateway-env".path;
          ExecStart = "${economicsGatewayRunner}";
          Restart = "always";
          RestartSec = "10";
          TimeoutStopSec = "210s";
        };

        Install.WantedBy = [ "default.target" ];
      };

      systemd.user.services.hermes-health-gateway = {
        Unit = {
          Description = "Hermes Agent health messaging gateway (Discord)";
          After = [
            "network-online.target"
            "sops-nix.service"
          ];
          Wants = [ "network-online.target" ];
        };

        Service = {
          Environment = [
            "HERMES_HOME=%h/.hermes"
            "DISCORD_ALLOWED_USERS=${discordUserId}"
            # Health bot is restricted to the dedicated #health channel, so it may
            # respond without explicit mentions there.
            "DISCORD_REQUIRE_MENTION=false"
            "PATH=${gatewayPath}"
            "GOOGLE_HEALTH_ENV_FILE=${healthGoogleEnvFile}"
          ];
          # DISCORD_HEALTH_BOT_TOKEN is the health bot token. The wrapper maps it to
          # the DISCORD_BOT_TOKEN name consumed by Hermes' Discord adapter.
          EnvironmentFile = config.sops.secrets."hermes-gateway-env".path;
          ExecStart = "${healthGatewayRunner}";
          Restart = "always";
          RestartSec = "10";
          TimeoutStopSec = "210s";
        };

        Install.WantedBy = [ "default.target" ];
      };
    })
  ];
}
