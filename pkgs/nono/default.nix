{
  nono,
  fetchFromGitHub,
  gitMinimal,
  rustPlatform,
}:

nono.overrideAttrs (oldAttrs: rec {
  version = "0.68.0";

  src = fetchFromGitHub {
    owner = "nolabs-ai";
    repo = "nono";
    rev = "v${version}";
    hash = "sha256-RxVYatzKjv6LJ+M4Js+sTvg0hMnovXxtr6WxwFYF16Y=";
  };

  cargoHash = "sha256-9gMhW2qt5gbf6x/uPLc4vl3rn6UdneoxRmWpeRqI4V0=";
  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit src;
    hash = cargoHash;
  };
  nativeCheckInputs = (oldAttrs.nativeCheckInputs or [ ]) ++ [ gitMinimal ];

  # IoctlDev パッチは v0.16.0 で上流修正済み（apply_with_abi() でデバイスパスのみ選択的付与）
  postPatch = (oldAttrs.postPatch or "") + ''
    # Seccomp deny should return EACCES (not EPERM) so glibc's dynamic linker
    # continues searching RUNPATH entries instead of aborting on the first miss.
    # v0.14.0 → v0.42.0 でコードがリファクタリングされ、deny_notif() が
    # respond_notif_errno() ヘルパー関数を使うようになった。
    substituteInPlace crates/nono/src/sandbox/linux.rs \
      --replace-fail \
        'respond_notif_errno(notify_fd, notif_id, libc::EPERM)' \
        'respond_notif_errno(notify_fd, notif_id, libc::EACCES)'

    # Seccomp-notify の対話プロンプトはマルチスレッドの子プロセス (Node.js) で
    # デッドロックを引き起こす。プロンプト待機中に他スレッドの通知がキューに溜まり、
    # 応答後にスーパーバイザーがハングし、Ctrl-C も効かなくなる。
    # ターミナル判定を opt-in 環境変数に置き換え、デフォルトで自動拒否にする。
    # NONO_INTERACTIVE_PROMPT=1 を設定すれば従来の対話モードに戻せる。
    substituteInPlace crates/nono-cli/src/terminal_approval.rs \
      --replace-fail \
        'if !stderr.is_terminal() {' \
        'if std::env::var_os("NONO_INTERACTIVE_PROMPT").is_none() {'
  '';

  # nixpkgs masterの0.68.0 packageで追加済みのbuild-sandbox依存skip。
  # nixos-unstable側のpackage expressionが追いついたら、この差分は削除できる。
  checkFlags = (oldAttrs.checkFlags or [ ]) ++ [
    "--skip=test_restrict_execute_does_not_break_rename_into_new_subdir"
    "--skip=granted_path_exits_zero"
    "--skip=env_credentials_with_command_policies_non_shim_entry_succeeds"
    "--skip=proxy_runtime::tests::capture_helper_with_interaction_stdin_true_inherits_terminal_stdin"
    "--skip=proxy_runtime::tests::capture_helper_with_stdio_true_receives_null_not_terminal_stdin"
    "--skip=proxy_runtime::tests::proxy_credential_capture_backend_captures_and_caches"
    "--skip=proxy_runtime::tests::proxy_credential_capture_backend_parses_json_headers"
    "--skip=proxy_runtime::tests::proxy_credential_capture_backend_rejects_empty_stdout"
    "--skip=proxy_runtime::tests::proxy_credential_capture_backend_sends_request_json_stdin"
    "--skip=proxy_runtime::tests::proxy_credential_capture_backend_uses_path_cache_scope"
    "--skip=server::tests::reactive_proxy_auth_retry_answered_after_407"
    "--skip=server::tests::test_oauth_capture_routes_activate_intercept"
    "--skip=server::tests::test_route_diagnostics_groups_credential_and_endpoint_routes"
  ];

  meta = oldAttrs.meta // {
    homepage = "https://github.com/nolabs-ai/nono";
    changelog = "https://github.com/nolabs-ai/nono/blob/v${version}/CHANGELOG.md";
  };

})
