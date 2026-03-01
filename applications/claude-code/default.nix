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
  # --profile claude-code: 組み込みプロファイルで workdir readwrite, ~/.claude,
  #   interactive mode, unlink_protection, PostToolUseFailure フック等を有効化
  # 追加フラグ: プロファイルでカバーされない NixOS 固有パス、/dev/null（nono バグ回避）、
  #   dangerous_commands の許可
  claudeWrapped = pkgs.writeShellScriptBin "claude" ''
    if ! command -v ${pkgs.nono}/bin/nono &>/dev/null; then
      echo "Error: nono is not available. Use claude-raw for unprotected access." >&2
      exit 1
    fi

    # ~/.claude.json を ~/.claude/ 内にシンボリンクで移動
    # write-file-atomic が temp ファイルを同ディレクトリに作成するため、
    # プロファイルの allow_file では不足（親ディレクトリの MakeReg が必要）
    if [ -f "$HOME/.claude.json" ] && [ ! -L "$HOME/.claude.json" ]; then
      mv "$HOME/.claude.json" "$HOME/.claude/claude.json"
      ln -s "$HOME/.claude/claude.json" "$HOME/.claude.json"
    elif [ ! -e "$HOME/.claude.json" ]; then
      touch "$HOME/.claude/claude.json"
      ln -s "$HOME/.claude/claude.json" "$HOME/.claude.json"
    fi

    # Claude Code は SHELL に "bash" か "zsh" を含むパスのみ受け付ける。
    # NixOS では /bin/bash が存在せず、$SHELL (~/.nix-profile/bin/zsh) は
    # nono の Landlock パス外。/bin/sh のシンボリンク解決先は
    # /nix/store/...-bash-interactive-.../bin/bash なので "bash" を含む。
    export SHELL=$(${pkgs.coreutils}/bin/readlink -f /bin/sh)

    exec ${pkgs.nono}/bin/nono run \
      --profile claude-code \
      --allow-cwd \
      --allow "$HOME/ghq/github.com/Yus314" \
      --allow "$HOME/.local/share" \
      --allow "$HOME/.cache" \
      --allow "$HOME/.config/codex" \
      --read "$HOME/.config/gh" \
      --read "$HOME/.nix-profile" \
      --allow-file /dev/null \
      --allow-command rm \
      --allow-command mv \
      --allow-command cp \
      --allow-command chmod \
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
        # nono サンドボックス診断 — 操作失敗時に制約情報を Claude に通知
        # HM が settings.json を管理するため nono の自動インストールが失敗する。
        # スクリプト本体は nono が ~/.claude/hooks/nono-hook.sh に配置する。
        PostToolUseFailure = [
          {
            matcher = "Read|Write|Edit|Bash";
            hooks = [
              {
                type = "command";
                command = "$HOME/.claude/hooks/nono-hook.sh";
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
