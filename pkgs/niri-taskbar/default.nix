{
  lib,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  gtk3,
  glib,
  dbus,
  libdbusmenu-gtk3,
  wayland,
}:

rustPlatform.buildRustPackage rec {
  pname = "niri-taskbar";
  version = "0.2.0+niri.25.05";

  src = fetchFromGitHub {
    owner = "LawnGnome";
    repo = "niri-taskbar";
    rev = "v${version}";
    hash = "sha256-2DemaNMzdUjziRvDah4ZvYsyu44+EuSe2w55t21hPws=";
  };

  useFetchVendor = true;
  cargoHash = "sha256-AqlYhJjcxHle4APGKzjU60oJFdzZnSjX4KQ9t/xX9xA=";

  nativeBuildInputs = [
    pkg-config
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    gtk3
    glib
    dbus
    libdbusmenu-gtk3
    wayland
  ];

  # Waybar CFFFIモジュールとしてビルド
  #cargoBuildType = "release";

  # installPhaseを上書きして、共有ライブラリを正しくインストールする
  installPhase = ''
    runHook preInstall

    # installコマンドで.soファイルを$out/libにインストールする
    # これにより、後のfixupPhaseでpatchelfが自動的に適用される
    install -Dm644 "target/x86_64-unknown-linux-gnu/release/libniri_taskbar.so" -t "$out/lib"

    runHook postInstall
  '';

  # メタデータ
  meta = with lib; {
    description = "Niri taskbar module for Waybar";
    homepage = "https://github.com/LawnGnome/niri-taskbar";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
    mainProgram = "niri-taskbar";
  };
}
