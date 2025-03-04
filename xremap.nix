{
  lib,
  fetchFromGitHub,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "xremap";
  version = "0.10.2";

  src = fetchFromGitHub {
    owner = "Yus314";
    repo = pname;
    rev = "v${version}";
    sha256 = "1gcp4gbmf1v2xjx00j6b19jl2alk2v9s5v97qi240gm8k274kr9w";

  };
  #cargoSha256 = "sha256-XXWfHIQr9V+yPW12w37CYJ3PymMtshLwN9fO+hcEnkI=";
  cargoHash = "sha256-XXWfHIQr9V+yPW12w37CYJ3PymMtshLwN9fO+hcEnkI=";

  buildNoDefaultFeatures = true;
  buildFeatures = [ "wlroots" ];

  meta = with lib; {
    description = "xeremap is a key remapper for Linux.";
    longDescription = ''
      xremap is a key remapper for Linux. Unlike xmodmap, it supports app-specific remapping and Wayland.
    '';
    changlog = "https://github.com/k0kubun/xremap/releasen/tag/v${version}";
    license = licenses.mit;
  };
}
