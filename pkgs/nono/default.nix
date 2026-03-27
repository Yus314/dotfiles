{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  dbus,
  stdenv,
}:

rustPlatform.buildRustPackage rec {
  pname = "nono";
  version = "0.25.0";

  src = fetchFromGitHub {
    owner = "always-further";
    repo = "nono";
    rev = "v${version}";
    hash = "sha256-CwlO6qRQ6VrgQGmusJb6/RWKxDyApsh8YLYf5MDBYOY=";
  };

  cargoHash = "sha256-DfGjB1wx7JMXszS8RTbKZl13hdBEKOWUFpaUigNuTGg=";

  # IoctlDev パッチは v0.16.0 で上流修正済み（apply_with_abi() でデバイスパスのみ選択的付与）
  postPatch = ''
    # Seccomp deny should return EACCES (not EPERM) so glibc's dynamic linker
    # continues searching RUNPATH entries instead of aborting on the first miss.
    # v0.14.0 → v0.25.0 でコードがリファクタリングされ、deny_notif() が
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

  # テストは Nix サンドボックス内で利用できないカーネル機能
  # (Landlock, seccomp-notify) を必要とするためスキップ
  doCheck = false;

  # CLI のみビルド（nono-ffi を除外）
  cargoBuildFlags = [
    "--package"
    "nono-cli"
  ];

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    openssl
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ dbus ];

  meta = {
    description = "Kernel-level sandbox for AI coding agents";
    homepage = "https://github.com/always-further/nono";
    license = lib.licenses.asl20;
    mainProgram = "nono";
  };
}
