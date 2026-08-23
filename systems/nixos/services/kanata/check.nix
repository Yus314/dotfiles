{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
in
pkgs.runCommand "shingeta-kanata-check"
  {
    nativeBuildInputs = [
      python
      pkgs.diffutils
      pkgs.kanata
    ];
  }
  ''
    python ${./generate_shingeta.py} \
      --source ${../xremap/shingeta.yml} \
      --output generated.kbd

    if ! cmp -s generated.kbd ${./shingeta.kbd}; then
      echo "generated Kanata config differs from committed shingeta.kbd" >&2
      diff -u ${./shingeta.kbd} generated.kbd >&2 || true
      exit 1
    fi

    {
      cat <<'EOF'
    (defcfg
      process-unmapped-keys yes
      concurrent-tap-hold yes
      linux-continue-if-no-devs-found yes)
    EOF
      cat generated.kbd
    } > full.kbd

    kanata --cfg full.kbd --check --debug
    touch "$out"
  ''
