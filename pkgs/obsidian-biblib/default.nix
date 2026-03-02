{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  version = "1.8.0";
  baseUrl = "https://github.com/callumalpass/obsidian-biblib/releases/download/${version}";
in
stdenvNoCC.mkDerivation {
  pname = "obsidian-biblib";
  inherit version;

  dontUnpack = true;

  mainJs = fetchurl {
    url = "${baseUrl}/main.js";
    hash = "sha256-S3hy1sK45ofxz7PlWOIS/P996stX4BqTdxvfcfNXdRY=";
  };
  manifestJson = fetchurl {
    url = "${baseUrl}/manifest.json";
    hash = "sha256-WvpRx8CNo29nvw9xGeZhhyCq52LBNUuIY4o1G8YxcWM=";
  };
  stylesCss = fetchurl {
    url = "${baseUrl}/styles.css";
    hash = "sha256-MVWmrI3UD2GK/0Oax0tDjEcM/xmeJ5Q7zFwdOaSB7To=";
  };

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp $mainJs $out/main.js
    cp $manifestJson $out/manifest.json
    cp $stylesCss $out/styles.css
    runHook postInstall
  '';

  meta = {
    description = "Obsidian plugin for managing bibliographic references and literature notes";
    homepage = "https://github.com/callumalpass/obsidian-biblib";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
