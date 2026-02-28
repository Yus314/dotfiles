{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  dbus,
  darwin,
  stdenv,
}:

rustPlatform.buildRustPackage rec {
  pname = "nono";
  version = "0.6.1";

  src = fetchFromGitHub {
    owner = "always-further";
    repo = "nono";
    rev = "v${version}";
    hash = "sha256-EAxgz7qCXLztV83UZimcImGbbTCC8EJVJiXlBr0T1NY=";
  };

  cargoHash = "sha256-GagTF5eTdhU+wyK9R1ltLVfM48qF1XH+eTKbaqA8umE=";

  # Landlock V5 (kernel 6.10+) の IoctlDev 権限が access_to_landlock() で
  # 付与されないバグを修正。TTY ioctl (setRawMode 等) がブロックされる。
  # https://github.com/always-further/nono/issues/XXX
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
  ++ lib.optionals stdenv.hostPlatform.isLinux [ dbus ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    darwin.apple_sdk.frameworks.Security
    darwin.apple_sdk.frameworks.SystemConfiguration
  ];

  meta = {
    description = "Kernel-level sandbox for AI coding agents";
    homepage = "https://github.com/always-further/nono";
    license = lib.licenses.asl20;
    mainProgram = "nono";
  };
}
