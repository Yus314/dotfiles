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
  version = "0.11.0";

  src = fetchFromGitHub {
    owner = "always-further";
    repo = "nono";
    rev = "v${version}";
    hash = "sha256-/pfWJDBgkGpCLuW4288JhhlFtrEEMdHoclPPsAkI+Ps=";
  };

  cargoHash = "sha256-dzDOIIhaL8K0Kf5uh6hQOiWM5tKeeCKVrmvd8HjDlJU=";

  # Landlock V5 (kernel 6.10+) の IoctlDev 権限が access_to_landlock() で
  # 付与されないバグを修正。TTY ioctl (setRawMode 等) がブロックされる。
  postPatch = ''
    substituteInPlace crates/nono/src/sandbox/linux.rs \
      --replace-fail \
        'AccessMode::Read => AccessFs::ReadFile | AccessFs::ReadDir | AccessFs::Execute,' \
        'AccessMode::Read => AccessFs::ReadFile | AccessFs::ReadDir | AccessFs::Execute | AccessFs::IoctlDev,'
  '';

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
