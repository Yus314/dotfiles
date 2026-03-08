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
  version = "0.12.0";

  src = fetchFromGitHub {
    owner = "always-further";
    repo = "nono";
    rev = "v${version}";
    hash = "sha256-ZDTY/NDNHSQ0JeEPTp6E0vXSnVW5X+2zvwprU1/4Khk=";
  };

  cargoHash = "sha256-DzLw8bGfSUIg8vsj2IKOHG1MTvqoye9YXz1pz6Jy2WI=";

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
