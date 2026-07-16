# Hermes Agent — always-on messaging gateway (Discord), run as a home-manager
# user service so the Codex (ChatGPT) OAuth login lives in your own ~/.hermes.
#
# Built from the headless fork (web/TUI dashboards stubbed out) because the
# upstream Nix package's web/tui build is currently broken — see upstream
# NousResearch/hermes-agent#27430. Once that lands, repoint the flake input
# back to upstream and retire the fork.
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
  hermes = inputs.hermes-agent.packages.${pkgs.system}.messaging.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.patch ];
    postInstall = (old.postInstall or "") + ''
      mkdir -p "$out/lib/hermes-patched"
      cp -R ${inputs.hermes-agent}/hermes_cli "$out/lib/hermes-patched/hermes_cli"
      chmod -R u+w "$out/lib/hermes-patched/hermes_cli"
      patch -d "$out/lib/hermes-patched" -p1 < ${./kanban-external-skills.patch}
      for executable in hermes hermes-agent hermes-acp; do
        wrapProgram "$out/bin/$executable" \
          --prefix PYTHONPATH : "$out/lib/hermes-patched"
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

  # Your Discord user id — only this account may talk to the bot
  # (same id used by the openclaw gateway).
  discordUserId = "885083579367972874";

  gatewayPath = "${agentBrowser}/bin:${pkgs.nodejs_24}/bin:%h/.nix-profile/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin";
  healthGoogleEnvFile = config.sops.secrets."hermes-health-google-env".path;
  hermesConfigPython = pkgs.python312.withPackages (ps: [ ps.pyyaml ]);
  gatewayPreflight = ./scripts/gateway_preflight.py;
  gatewayChannelsConfig = ./scripts/gateway_channels_config.py;
  researchConfig = ./scripts/research_config.py;

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
    hermes
    agentBrowser
    pkgs.nodejs_24
    pkgs.uv
  ];

  home.file = {
    ".hermes/mcp/research_providers_server.py".source = ./research_providers_server.py;
    ".hermes/skins/modus-vivendi.yaml".text = modusVivendiSkin;
    ".hermes/skins/modus-operandi.yaml".text = modusOperandiSkin;
  };

  home.activation.hermesResearchProvidersConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${hermesConfigPython}/bin/python ${researchConfig} "$HOME/.hermes/config.yaml"
  '';

  home.activation.hermesGatewayChannels =
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "hermesResearchProvidersConfig"
      ]
      ''
        $DRY_RUN_CMD ${hermesConfigPython}/bin/python ${gatewayChannelsConfig} ${lib.escapeShellArg (builtins.toJSON gatewayChannels)}
      '';

  systemd.user.services.hermes-gateway = {
    Unit = {
      Description = "Hermes Agent messaging gateway (Discord)";
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
      # The wrapper validates the default channel allowlist and removes all
      # profile-specific Discord tokens before starting Hermes.
      EnvironmentFile = config.sops.secrets."hermes-gateway-env".path;
      ExecStart = "${defaultGatewayRunner}";
      # Retries until the one-time `hermes model` (Codex auth) has populated
      # ~/.hermes (auth.json + config.yaml).
      Restart = "always";
      RestartSec = "10";
      # Hermes drains in-flight gateway sessions for up to
      # agent.restart_drain_timeout=180s; keep systemd's stop timeout above
      # that so restarts do not SIGKILL active agents mid-drain.
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
}
