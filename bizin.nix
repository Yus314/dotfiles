{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation rec {
  pname = "bizin-gothic-nf";
  version = "0.0.4";

  src = fetchzip {
    url = "https://github.com/yuru7/bizin-gothic/releases/download/v${version}/BizinGothicNF_v${version}.zip";
    hash = "sha256-k0pGSuH6Jq5BX/a4vp7zd9hdDrfJACAa2Jb1OqPXlWs=";
  };

  installPhase = ''
    runHook preInstall

    install -Dm644 *.ttf -t $out/share/fonts/bizin-gothic-nf

    runHook postInstall
  '';

  meta = with lib; {
    description = "Composite font of Hack, GenJyuu-Gothic and nerd-fonts";
    homepage = "https://github.com/yuru7/HackGen";
    license = licenses.ofl;
    platforms = platforms.all;
  };
}
