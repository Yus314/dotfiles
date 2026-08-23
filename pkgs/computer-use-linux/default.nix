{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  dbus,
}:
rustPlatform.buildRustPackage rec {
  pname = "computer-use-linux";
  version = "0.4.1";

  src = fetchFromGitHub {
    owner = "agent-sh";
    repo = "computer-use-linux";
    rev = "v${version}";
    hash = "sha256-ii5lluOpjv2/KPMV06ze8VXuqKowgeCOx7nur5MyDgg=";
  };

  cargoHash = "sha256-TsnknqiQXgTeON/1/YlWQm8mP7bnW3FYk7j8Y3dHwtY=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ dbus ];

  meta = {
    description = "Linux desktop control over MCP";
    homepage = "https://github.com/agent-sh/computer-use-linux";
    license = lib.licenses.mit;
    mainProgram = "computer-use-linux";
    platforms = lib.platforms.linux;
  };
}
