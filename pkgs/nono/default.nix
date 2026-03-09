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
  version = "0.14.0";

  src = fetchFromGitHub {
    owner = "always-further";
    repo = "nono";
    rev = "v${version}";
    hash = "sha256-oa5ng8WQQm47bCWnmAK4u2JElYyiof98ytYyUd5GQPk=";
  };

  cargoHash = "sha256-qAKcKslVrz7qZzMyS9PaBC+9bWlV6WqQeDJrKHVdJps=";

  # Landlock V5 (kernel 6.10+) の IoctlDev 権限が access_to_landlock() で
  # 付与されないバグを修正。TTY ioctl (setRawMode 等) がブロックされる。
  postPatch = ''
    substituteInPlace crates/nono/src/sandbox/linux.rs \
      --replace-fail \
        'AccessMode::Read => AccessFs::ReadFile | AccessFs::ReadDir | AccessFs::Execute,' \
        'AccessMode::Read => AccessFs::ReadFile | AccessFs::ReadDir | AccessFs::Execute | AccessFs::IoctlDev,'

    # Seccomp deny should return EACCES (not EPERM) so glibc's dynamic linker
    # continues searching RUNPATH entries instead of aborting on the first miss.
    substituteInPlace crates/nono/src/sandbox/linux.rs \
      --replace-fail \
        'error: -libc::EPERM,' \
        'error: -libc::EACCES,'

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

  # v0.14.0 のテストは Nix サンドボックス内で利用できないカーネル機能
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
