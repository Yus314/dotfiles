{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  codexConfigDir =
    if config.home.preferXdgDirectories then
      "${config.xdg.configHome}/codex"
    else
      "${config.home.homeDirectory}/.codex";
  codexConfigKey =
    if config.home.preferXdgDirectories then
      "${lib.removePrefix config.home.homeDirectory config.xdg.configHome}/codex/config.toml"
    else
      ".codex/config.toml";
  configPython = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);
  mutableConfig = pkgs.runCommand "codex-mutable-config" { } ''
    cp ${./mutable_config.py} mutable_config.py
    cp ${./test_mutable_config.py} test_mutable_config.py
    ${configPython}/bin/python test_mutable_config.py
    cp mutable_config.py "$out"
  '';

  # 通知スクリプト
  notifyScript =
    if isLinux then
      let
        # 音声設定（dunstと統一）
        soundPath = "${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo";
      in
      pkgs.writeShellScript "codex-notify" ''
        # JSONペイロードを引数から取得
        INPUT="$1"
        TYPE=$(echo "$INPUT" | ${pkgs.jq}/bin/jq -r '.type // "unknown"')
        MSG=$(echo "$INPUT" | ${pkgs.jq}/bin/jq -r '.["last-assistant-message"] // ""' | head -c 200)

        # 通知を送信
        ${pkgs.dunst}/bin/dunstify \
          -a "codex" \
          -u normal \
          -i "dialog-information" \
          "Codex: タスク完了" \
          "$MSG"

        # 完了音を再生
        ${pkgs.pipewire}/bin/pw-play "${soundPath}/complete.oga" --volume=0.8
      ''
    else
      pkgs.writeShellScript "codex-notify" ''
        INPUT="$1"
        MSG=$(echo "$INPUT" | ${pkgs.jq}/bin/jq -r '.["last-assistant-message"] // ""' | head -c 200)
        osascript -e "display notification \"$MSG\" with title \"Codex: タスク完了\""
      '';
in
{
  # sops.nix設定 - OpenAI API KEY
  sops.secrets = {
    "codex-openai-api-key" = {
      sopsFile = ./secrets.yaml;
      path = "${config.xdg.configHome}/codex/openai_api_key";
      key = "openai_api_key";
      mode = "0600";
    };
  };

  programs.codex = {
    enable = true;
    package = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
    settings = {
      # 0.157 enables daemon auto-start, but codex-cli-nix lacks codex-package.json.
      # Keep embedded sessions until the Nix package supports managed daemons.
      features.daemon_auto_start = false;
      model_reasoning_effort = "xhigh";
      sandbox_mode = "workspace-write";
      approval_policy = "on-request";
      sandbox_workspace_write = {
        network_access = true;
      };
      # 外部通知コマンド（音声付き、フォーカス状態問わず発火）
      notify = [ "${notifyScript}" ];
      tui = {
        # approval-requested用にtui通知も維持
        notifications = [ "approval-requested" ];
        notification_method = "osc9";
      };
    };
  };

  # Codex persists trust and TUI state here. Keep HM's generated settings (including
  # MCP integration), but merge them into a regular file instead of a store link.
  home.file.${codexConfigKey}.enable = false;
  # Migrate BEFORE linkGeneration removes the old generation's config symlink.
  home.activation.codexMutableConfig =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        run ${configPython}/bin/python ${mutableConfig} \
          ${config.home.file.${codexConfigKey}.source} \
          ${lib.escapeShellArg "${codexConfigDir}/config.toml"}
      '';

  # Fish shellでOPENAI_API_KEY環境変数を設定
  programs.fish.interactiveShellInit = lib.mkAfter ''
    # Load OpenAI API key for Codex CLI
    if test -f "${config.xdg.configHome}/codex/openai_api_key"
      set -gx OPENAI_API_KEY (cat "${config.xdg.configHome}/codex/openai_api_key")
    end
  '';
}
