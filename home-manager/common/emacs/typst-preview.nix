{
  fetchFromGitHub,
  melpaBuild,
  websocket,
}:
melpaBuild rec {
  pname = "typst-preview";
  version = "20250328";
  src = fetchFromGitHub {
    owner = "havarddj";
    repo = "typst-preview.el";
    rev = "8d5d1f5bd70d9e6b2fa89295ac3a5802419305a2";
    sha256 = "sha256-pPYs74qIGvm4RAP9U5PnYkoeagAfVNsl6mW05BnFXlY=";
  };
  packageRequires = [
    websocket
  ];
}
