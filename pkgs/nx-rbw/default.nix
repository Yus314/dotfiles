{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation rec {
  pname = "nx-rbw";
  version = "unstable-2023-01-31";

  src = fetchurl {
    url = "https://codeberg.org/ablatedsprocket/nx-rbw/archive/main.tar.gz";
    sha256 = "sha256-zkcT9hM2JSHhYfJSLldYKg31BLHto3rbfhHGZZvkfAk=";
  };

  patches = [ ./fix-folder-handling.patch ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r * $out/

    runHook postInstall
  '';

  meta = with lib; {
    description = "RBW (Rust BitWarden) integration for Nyxt browser";
    homepage = "https://codeberg.org/ablatedsprocket/nx-rbw";
    license = licenses.gpl3Plus;
    platforms = platforms.all;
    maintainers = with maintainers; [ ];
  };
}
