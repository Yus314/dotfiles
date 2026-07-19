{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  claudeConfigDir = "${config.xdg.configHome}/claude";

  claudeCodePkg = pkgs.claude-code;
  nonoClaudePack = pkgs.fetchFromGitHub {
    owner = "nolabs-ai";
    repo = "nono-packs";
    rev = "claude-v0.1.0";
    hash = "sha256-JXYel5cRcjDQwhOraL6OJIHpGUVk8fdzNJmB5y3yqFA=";
  };

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
  # --profile claude-code-nixos: ローカル固定したXDG対応プロファイルを extends し、
  #   NixOS 固有パスを追加（~/.config/nono/profiles/ に配置）
  # allow を細分化して keyrings deny との overlap を回避
  claudeWrapped = pkgs.writeShellScriptBin "claude" ''
    if ! command -v ${pkgs.nono}/bin/nono &>/dev/null; then
      echo "Error: nono is not available. Use claude-raw for unprotected access." >&2
      exit 1
    fi

    # LandlockではHOMEを含む親directoryを許可して、その配下のcredentialだけをdenyできない。
    # --allow-cwdがHOMEを再帰許可してdeny-overlapになる前に、明示的にfail closedする。
    if ! cwd_path="$(${pkgs.coreutils}/bin/realpath -- .)" \
      || ! home_path="$(${pkgs.coreutils}/bin/realpath -- "$HOME")"; then
      echo "Error: could not resolve HOME or the current working directory safely." >&2
      exit 2
    fi
    if [ "$cwd_path" = "/" ] \
      || [ "$cwd_path" = "$home_path" ] \
      || [[ "$home_path" == "$cwd_path/"* ]]; then
      echo "Error: refusing to grant sandboxed Claude a working directory that contains HOME. Change to a project directory first." >&2
      exit 2
    fi

    export CLAUDE_CONFIG_DIR=${lib.escapeShellArg claudeConfigDir}
    ${pkgs.coreutils}/bin/install -d -m 700 "$CLAUDE_CONFIG_DIR"

    # ~/.claude.json を CLAUDE_CONFIG_DIR 内にシンボリンクで移動
    # write-file-atomic が temp ファイルを同ディレクトリに作成するため、
    # プロファイルの allow_file では不足（親ディレクトリの MakeReg が必要）
    if [ -f "$HOME/.claude.json" ] && [ ! -L "$HOME/.claude.json" ]; then
      mv "$HOME/.claude.json" "$CLAUDE_CONFIG_DIR/claude.json"
      ln -s "$CLAUDE_CONFIG_DIR/claude.json" "$HOME/.claude.json"
    elif [ ! -e "$HOME/.claude.json" ]; then
      touch "$CLAUDE_CONFIG_DIR/claude.json"
      ln -s "$CLAUDE_CONFIG_DIR/claude.json" "$HOME/.claude.json"
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
    # ネットワークはprofileで許可（--allow-net は deprecated）。
    # O_CREAT 問題は v0.15.0 (PR #289) で修正済み。
    #
    # --allow-gpu: macOS (Apple Silicon) では Metal の AGXDeviceUserClient へ
    # iokit-open を許可する。Linux では DRM/NVIDIA/ROCm のデバイスノードを
    # 列挙し、見つからないと SandboxInit エラーで fail closed するため、
    # GPU 非搭載ホスト (ryuk/rem 等) を考慮して macOS でのみ有効化する。
    exec ${pkgs.nono}/bin/nono run \
      --profile claude-code-nixos \
      --allow-cwd \
      ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "--allow-gpu"} \
      -- ${claudeCodePkg}/bin/claude \
        --dangerously-skip-permissions \
        "$@"
  '';

  # 素の Claude Code（リスク承知で PATH に残す）
  claudeRaw = pkgs.writeShellScriptBin "claude-raw" ''
    export CLAUDE_CONFIG_DIR=${lib.escapeShellArg claudeConfigDir}
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

  # nolabs-ai/claude pack v0.1.0由来のprofileをローカル固定する。
  # registry packを直接継承すると、初回実行時に未固定pullとClaude設定変更が発生する。
  # nono 0.68.0は`claude-code`というprofile名を継承するだけで、実効grantに関係なく
  # legacy ~/.claude を事前作成する。XDGを正本にするため特殊名を避ける。
  xdg.configFile."nono/profiles/claude-xdg-base.json".text = builtins.toJSON {
    extends = "default";
    meta = {
      name = "claude-xdg-base";
      version = "1.0.0";
      description = "Locally pinned Claude Code profile derived from nolabs-ai/claude 0.1.0";
      author = "nolabs-ai";
    };
    groups.include = [
      {
        name = "claude_code_macos";
        when = "macos";
      }
      {
        name = "claude_code_linux";
        when = "linux";
      }
      {
        name = "user_caches_macos";
        when = "macos";
      }
      {
        name = "claude_cache_linux";
        when = "linux";
      }
      "node_runtime"
      "rust_runtime"
      "python_runtime"
      {
        name = "vscode_macos";
        when = "macos";
      }
      {
        name = "vscode_linux";
        when = "linux";
      }
      {
        name = "linux_sysfs_read";
        when = "linux";
      }
      "nix_runtime"
      "git_config"
      "unlink_protection"
    ];
    security = {
      signal_mode = "isolated";
      capability_elevation = false;
    };
    filesystem = {
      allow = [
        "$XDG_CONFIG_HOME/claude"
        "$XDG_CONFIG_HOME/claude.lock"
        "$HOME/.local/state/claude/locks"
        "$HOME/.cache/claude"
        "$NONO_CONFIG/profile-drafts"
        "/tmp/claude-$UID"
        {
          path = "$HOME/Library/Keychains";
          when = "macos";
        }
      ];
      read = [
        "$NONO_PACKAGES"
        "$NONO_CONFIG/profiles"
      ];
      allow_file = [
        "$HOME/.claude.json"
        "$HOME/.claude.json.lock"
        "$HOME/.claude.lock"
      ];
      bypass_protection = [
        {
          path = "$HOME/Library/Keychains";
          when = "macos";
        }
      ];
    };
    network.block = false;
    workdir.access = "readwrite";
    open_urls = {
      allow_origins = [
        "https://claude.ai"
        "https://claude.com"
        "https://api.anthropic.com"
        "https://platform.claude.com"
      ];
      allow_localhost = true;
    };
    diagnostics.suppress_system_services = [ "forbidden-exec-sugid" ];
    allow_launch_services = true;
    undo = {
      exclude_patterns = [
        "node_modules"
        ".next"
        "__pycache__"
        "target"
      ];
      exclude_globs = [ "*.tmp.[0-9]*.[0-9]*" ];
    };
    interactive = true;
  };

  # カスタム nono プロファイル: ローカル固定baseをextendsし、ホスト固有設定を追加
  xdg.configFile."nono/profiles/claude-code-nixos.json".text = builtins.toJSON {
    extends = "claude-xdg-base";
    # network セクション削除: proxy_allow が存在するだけで nono v0.37.1 は
    # プロキシモードを有効化し、macOS Seatbelt で spawn EPERM を引き起こす。
    # 現行版でもデフォルト許可のため proxy_allow 自体が不要。
    #
    # security.allowed_commands 削除: v0.33.0 で deprecated（カーネル非強制）。
    # ファイルシステム権限で十分にカバーされる。
    #
    # allow_gpu: macOS (Apple Silicon) では AGXDeviceUserClient への iokit-open を
    # 許可。nono は CLI 側の --allow-gpu とプロファイル側の opt-in の両方が
    # 揃ったときだけ Seatbelt にルールを足すため、ここで profile_allowed=true
    # にする。Linux 側のラッパーは --allow-gpu を付けないので no-op。
    allow_gpu = true;
    filesystem = {
      allow = [
        "$HOME/ghq/github.com/Yus314"
        "$HOME/ledger"
        "$HOME/Maildir"
        "$HOME/.local/share/nix"
        "$HOME/.local/share/direnv"
        "$HOME/.local/share/zoxide"
        "$HOME/.local/share/gnupg"
        "$HOME/.cache"
        "$HOME/.local/share/cargo"
        "$HOME/.local/state/cabal"
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

  # registry packの暗黙pullを避けつつ、同packの診断hookを固定配置する。
  xdg.configFile."claude/hooks/nono-hook.sh" = {
    source = "${nonoClaudePack}/claude/bin/nono-hook.sh";
    executable = true;
  };
  xdg.configFile."claude/hooks/nono-hook-bash.sh" = {
    source = "${nonoClaudePack}/claude/bin/nono-hook-bash.sh";
    executable = true;
  };

  home.packages = [
    (lib.hiPrio claudeWrapped)
    claudeRaw
    pkgs.nono
  ];

  # Claude Code がシンボリックリンクを通常ファイルに置き換えた場合でも
  # switch 時に確認なしで再作成する
  home.file."${config.programs.claude-code.configDir}/CLAUDE.md".force = true;

  programs.claude-code = {
    enable = true;
    configDir = claudeConfigDir;
    context = ''
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
        # nono sandbox denialを、成功扱いのBash結果からも検出する。
        PostToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "${claudeConfigDir}/hooks/nono-hook-bash.sh";
              }
            ];
          }
        ];
        # nono sandbox denialを、失敗したtool結果から検出する。
        PostToolUseFailure = [
          {
            matcher = "Read|Write|Edit|Bash";
            hooks = [
              {
                type = "command";
                command = "${claudeConfigDir}/hooks/nono-hook.sh";
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
