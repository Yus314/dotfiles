{
  pkgs ? import <nixpkgs> { },
  host ? "lawliet",
}:
assert builtins.elem host [
  "lawliet"
  "watari"
];
pkgs.runCommand "hermes-math-profile-${host}-candidate" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  cp -R ${./.} bundle
  chmod -R u+w bundle
  python bundle/scripts/refresh_manifest.py
  mkdir -p "$out"
  python bundle/scripts/build_candidate.py --host ${host} --output "$out/profile"
''
