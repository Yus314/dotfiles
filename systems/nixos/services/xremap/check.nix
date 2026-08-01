{ pkgs }:

pkgs.runCommand "shingeta-chord-symmetry-check"
  {
    nativeBuildInputs = [
      (pkgs.python3.withPackages (pythonPackages: [ pythonPackages.ruamel-yaml ]))
    ];
  }
  ''
    python ${./check_shingeta.py} ${./shingeta.yml}
    touch "$out"
  ''
