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
  # --profile claude-code-nixos: 組み込み claude-code プロファイルを extends し、
  #   NixOS 固有パス・allowed_commands を追加（~/.config/nono/profiles/ に配置）
  # allow を細分化して keyrings deny との overlap を回避
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

    # サンドボックス内では GPG 署名を無効化。
    # gpg-agent の pinentry はサンドボックス内の TTY に接続できないため、
    # パスフレーズキャッシュ切れ時に "No pinentry" で失敗する。
    # 必要なら push 前に git commit --amend -S で署名を追加できる。
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0=commit.gpgsign
    export GIT_CONFIG_VALUE_0=false

    # nono run はアダプティブ実行: Supervised/Direct を自動選択する。
    # v0.42.0 ではネットワークはデフォルト許可（--allow-net は deprecated）。
    # O_CREAT 問題は v0.15.0 (PR #289) で修正済み。
    exec ${pkgs.nono}/bin/nono run \
      --profile claude-code-nixos \
      --allow-cwd \
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

  # カスタム nono プロファイル: 組み込み claude-code を extends し NixOS 固有設定を追加
  xdg.configFile."nono/profiles/claude-code-nixos.json".text = builtins.toJSON {
    extends = "claude-code";
    # network セクション削除: proxy_allow が存在するだけで nono v0.37.1 は
    # プロキシモードを有効化し、macOS Seatbelt で spawn EPERM を引き起こす。
    # v0.42.0 でも引き続きデフォルト許可のため proxy_allow 自体が不要。
    #
    # security.allowed_commands 削除: v0.33.0 で deprecated（カーネル非強制）。
    # ファイルシステム権限で十分にカバーされる。
    filesystem = {
      allow = [
        "$HOME/ghq/github.com/Yus314"
        "$HOME/ledger"
        "$HOME/.local/share/nix"
        "$HOME/.local/share/direnv"
        "$HOME/.local/share/zoxide"
        "$HOME/.local/share/gnupg"
        "$HOME/.cache"
        "$HOME/.cargo"
        "$HOME/.config/codex"
        "/tmp"
      ];
      read = [
        "$HOME/.config/gh"
        "$HOME/.config/cabal"
        "$HOME/.nix-profile"
        # ~/.nix-profile → ~/.local/state/nix/profiles/profile のシンボリンク解決に必要
        "$HOME/.local/state/nix/profiles"
        # Claude Code がブラウザ検出で google-chrome config を probe する。
        # 未許可だと seccomp-notify の対話プロンプトが表示され、その間に
        # 他スレッドの通知がキューに溜まり、応答後にスーパーバイザーがハングする。
        "$HOME/.config/google-chrome"
      ];
    };
  };

  home.packages = [
    (lib.hiPrio claudeWrapped)
    claudeRaw
    pkgs.nono
  ];

  # Claude Code がシンボリックリンクを通常ファイルに置き換えた場合でも
  # switch 時に確認なしで再作成する
  home.file.".claude/CLAUDE.md".force = true;

  programs.claude-code = {
    enable = true;
    memory.text = ''
      <!-- nono-sandbox-start -->
      ## Nono Sandbox - CRITICAL

      **You are running inside the nono security sandbox.** This is a capability-based sandbox that CANNOT be bypassed or modified from within the session.

      ### On ANY "operation not permitted" or "EPERM" error:

      **IMMEDIATELY tell the user:**
      > This path is not accessible in the current nono sandbox session. You need to exit and restart with:
      > `nono run --allow /path/to/needed -- claude`

      **NEVER attempt:**
      - Alternative file paths or locations
      - Copying files to accessible directories
      - Using sudo or permission changes
      - Manual workarounds for the user to try
      - ANY other approach besides restarting nono

      The sandbox is a hard security boundary. Once applied, it cannot be expanded. The ONLY solution is to restart the session with additional --allow flags.
      <!-- nono-sandbox-end -->

      ## English Prompt Feedback

      The user is a native Japanese speaker practicing writing English prompts. After completing the main task response, provide English feedback on their prompt ONLY when there are improvements to suggest.

      Evaluate on three axes:
      1. **Naturalness**: Does it sound like a native speaker? Suggest more idiomatic alternatives.
      2. **Grammar**: Articles, prepositions, tense, subject-verb agreement, countable/uncountable nouns, etc.
      3. **Prompt effectiveness**: Is it clear, specific, and well-scoped for an AI coding assistant?

      Rules:
      - Skip feedback entirely if the English is natural and effective (no news is good news)
      - Place feedback at the END of your response, after a `---` separator
      - Format: original phrase → suggested improvement, with explanation
      - If the prompt is written in Japanese, skip feedback
    '';
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
