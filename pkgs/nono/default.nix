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
  version = "0.8.0";

  src = fetchFromGitHub {
    owner = "always-further";
    repo = "nono";
    rev = "v${version}";
    hash = "sha256-4GsG/xR/Ex2CJEqmv0TSfEMQyk/Se+Uja+n9jSo53/U=";
  };

  cargoHash = "sha256-0fxlIjsGOBjKeHUk+Ro+hk+20YBJLOXp6s0axuuyD4w=";

  # Landlock V5 (kernel 6.10+) の IoctlDev 権限が access_to_landlock() で
  # 付与されないバグを修正。TTY ioctl (setRawMode 等) がブロックされる。
  # https://github.com/always-further/nono/issues/XXX
  postPatch = ''
    substituteInPlace crates/nono/src/sandbox/linux.rs \
      --replace-fail \
        'AccessMode::Read => AccessFs::ReadFile | AccessFs::ReadDir | AccessFs::Execute,' \
        'AccessMode::Read => AccessFs::ReadFile | AccessFs::ReadDir | AccessFs::Execute | AccessFs::IoctlDev,'

    # deny_keychains_linux から ~/.local/share/keyrings を除去。
    # --allow "$HOME/.local/share" との Landlock deny-overlap 競合を回避。
    # 保護目標はホスト破壊防止であり、秘密漏洩は許容範囲。
    sed -i '/"~\/.local\/share\/keyrings"/d' \
      crates/nono-cli/data/policy.json
    # 末尾カンマ修正: "~/.op", → "~/.op"
    sed -i 's/"~\/.op",/"~\/.op"/' \
      crates/nono-cli/data/policy.json

    # rust_runtime グループから ~/.cargo を除去。
    # --allow "$HOME/.cargo" との read vs readwrite 競合を回避。
    # readwrite は CLI フラグ側で付与する。
    sed -i '/"~\/.cargo",/d' \
      crates/nono-cli/data/policy.json
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
