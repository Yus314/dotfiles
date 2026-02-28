{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  claudeCodePkg = pkgs.claude-code;

  notificationScript =
    if isLinux then
      pkgs.writeShellScript "claude-code-notification" ''
        ${pkgs.dunst}/bin/dunstify \
          -a "claude-code" \
          -u normal \
          -i "dialog-information" \
          "コマンド実行の確認" \
          "Claudeがコマンドの実行を確認したいようです"
      ''
    else
      pkgs.writeShellScript "claude-code-notification" ''
        osascript -e 'display notification "Claudeがコマンドの実行を確認したいようです" with title "Claude Code" subtitle "コマンド実行の確認" sound name "default"'
      '';

  stopScript =
    if isLinux then
      pkgs.writeShellScript "claude-code-stop" ''
        ${pkgs.dunst}/bin/dunstify \
          -a "claude-code" \
          -u normal \
          -i "emblem-checked" \
          "タスク完了" \
          "Claudeがあなたの依頼を完了させました!"
      ''
    else
      pkgs.writeShellScript "claude-code-stop" ''
        osascript -e 'display notification "Claudeがあなたの依頼を完了させました!" with title "Claude Code" subtitle "タスク完了" sound name "default"'
      '';

  # PreToolUse safety-net hook（Nix store 配置 = 不変 = 自己改ざん不可）
  safetyNetScript = pkgs.writeShellScript "claude-safety-net" ''
    INPUT=$(${pkgs.coreutils}/bin/cat)
    TOOL_NAME=$(echo "$INPUT" | ${pkgs.jq}/bin/jq -r '.tool_name // empty')

    if [ "$TOOL_NAME" != "Bash" ]; then
      exit 0
    fi

    COMMAND=$(echo "$INPUT" | ${pkgs.jq}/bin/jq -r '.tool_input.command // empty')

    # JSON パース失敗時は fail closed
    if [ -z "$COMMAND" ]; then
      echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Failed to parse command"}}'
      exit 0
    fi

    BLOCKED_PATTERNS=(
      'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f[[:space:]]+[/~.]'
      'sudo[[:space:]]'
      'git[[:space:]]+push[[:space:]]+.*--force'
      'git[[:space:]]+push[[:space:]]+.*-f[[:space:]]'
      'git[[:space:]]+reset[[:space:]]+--hard'
      'mkfs[[:space:]]'
      'dd[[:space:]]+if='
      ':\(\)\{[[:space:]]*:\|:&'
    )

    for pattern in "''${BLOCKED_PATTERNS[@]}"; do
      if echo "$COMMAND" | ${pkgs.gnugrep}/bin/grep -qE "$pattern"; then
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Blocked: $pattern\"}}"
        exit 0
      fi
    done

    exit 0
  '';

  # nono ラッパー（fail closed: nono 起動失敗時は即終了）
  claudeWrapped = pkgs.writeShellScriptBin "claude" ''
    if ! command -v ${pkgs.nono}/bin/nono &>/dev/null; then
      echo "Error: nono is not available. Use claude-raw for unprotected access." >&2
      exit 1
    fi

    # --allow-file はファイルの存在が前提（Landlock PathFd）
    touch "$HOME/.claude.json" 2>/dev/null || true

    exec ${pkgs.nono}/bin/nono run \
      --allow . \
      --allow "$HOME/.claude" \
      --read "$HOME/.local/share/claude" \
      --allow-file "$HOME/.claude.json" \
      --exec \
      -- ${claudeCodePkg}/bin/claude \
        --dangerously-skip-permissions \
        "$@"
  '';

  # 素の Claude Code（リスク承知で PATH に残す）
  claudeRaw = pkgs.writeShellScriptBin "claude-raw" ''
    exec ${claudeCodePkg}/bin/claude "$@"
  '';
in
{
  # sops.nix設定 - gh-token-for-mcp シークレット
  sops.secrets = {
    "gh-token-for-mcp" = {
      sopsFile = ../mcp/secrets.yaml;
    };
  };

  home.packages = [
    (lib.hiPrio claudeWrapped)
    claudeRaw
  ];

  programs.claude-code = {
    enable = true;
    settings = {
      includeCoAuthorBy = false;
      defaultMode = "bypassPermissions";
      env = {
        CLAUDE_CODE_ENABLE_TELEMETRY = "1";
        OTEL_METRICS_EXPORTER = "prometheus";
      };
      # Hook設定
      hooks = {
        # 安全ネット — 危険コマンドをブロック
        PreToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "${safetyNetScript}";
              }
            ];
          }
        ];
        # システム通知発生時
        Notification = [
          {
            hooks = [
              {
                type = "command";
                command = "${notificationScript}";
              }
            ];
          }
        ];
        # Claude応答完了時
        Stop = [
          {
            hooks = [
              {
                type = "command";
                command = "${stopScript}";
              }
            ];
          }
        ];
      };
    };
    agentsDir = ../../applications/claude-code/agents;
    commandsDir = ../../applications/claude-code/commands;
    skills = {
      codex = ./skills/codex;
    };
    mcpServers = import ../../applications/mcp {
      inherit inputs pkgs;
      ghTokenPath = config.sops.secrets.gh-token-for-mcp.path;
    };
  };
}
