# Hermes Agent — always-on messaging gateway (Discord), run as a home-manager
# user service so the Codex (ChatGPT) OAuth login lives in your own ~/.hermes.
#
# Built from the headless fork (web/TUI dashboards stubbed out) because the
# upstream Nix package's web/tui build is currently broken — see
# ./headless.patch and upstream NousResearch/hermes-agent#27430. Once that
# lands, repoint the flake input back to upstream and delete the patch/fork.
#
# One-time interactive setup (run as your user, on this host):
#   hermes model      # choose "OpenAI Codex" -> device-code login (ChatGPT
#                     #   Plus) -> set default model to gpt-5.3-codex
#   hermes fallback add openrouter/anthropic/claude-sonnet-4   # optional fallback
#   systemctl --user restart hermes-gateway
#
# Secret env (sops):  sops applications/hermes-agent/secrets.yaml
#   env: |
#     OPENROUTER_API_KEY=sk-or-...
#     DISCORD_BOT_TOKEN=...
{
  config,
  pkgs,
  inputs,
  ...
}:
let
  hermes = inputs.hermes-agent.packages.${pkgs.system}.messaging;

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

  home.packages = [
    hermes
    agentBrowser
    pkgs.nodejs_24
  ];

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
        "PATH=${agentBrowser}/bin:${pkgs.nodejs_24}/bin:%h/.nix-profile/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin"
      ];
      # OPENROUTER_API_KEY + DISCORD_BOT_TOKEN (dotenv, decrypted by sops)
      EnvironmentFile = config.sops.secrets."hermes-gateway-env".path;
      ExecStart = "${hermes}/bin/hermes gateway run";
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
}
