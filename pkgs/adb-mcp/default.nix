{
  lib,
  stdenv,
  fetchFromGitHub,
  buildNpmPackage,
}:

buildNpmPackage rec {
  pname = "adb-mcp";
  version = "unstable-2025-09-24";

  src = fetchFromGitHub {
    owner = "srmorete";
    repo = "adb-mcp";
    rev = "041729c0b25432df3199ff71b3163a307cf4c28c";
    hash = "sha256-AmD5ao94U2XiRlpDbpNg6X6o3KZvD/6fHInW2Hkhv94=";
  };

  npmDepsHash = "sha256-aBERp2Qv9tbGSrpIEFqBxf0OhrV+P64LYnm49xdKvQM=";

  meta = {
    description = "An MCP (Model Context Protocol) server for interacting with Android devices through ADB in TypeScript";
    homepage = "https://github.com/srmorete/adb-mcp";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ ];
    mainProgram = "adb-mcp";
    platforms = lib.platforms.all;
  };
}
