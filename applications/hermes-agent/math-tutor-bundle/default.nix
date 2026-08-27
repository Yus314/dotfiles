{
  pkgs ? import <nixpkgs> { },
  host ? "lawliet",
}:
assert builtins.elem host [
  "lawliet"
  "watari"
];
let
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  forbiddenSourceNames = [
    ".coverage"
    ".env"
    ".mypy_cache"
    ".pytest_cache"
    ".ruff_cache"
    "__pycache__"
    "auth.json"
    "cache"
    "caches"
    "candidate"
    "candidates"
    "credentials"
    "dist"
    "cron"
    "gateway"
    "logs"
    "oauth"
    "result"
    "sessions"
    "state.db"
    "state.db-shm"
    "state.db-wal"
  ];
  bundleSource = pkgs.lib.cleanSourceWith {
    src = ./.;
    filter =
      path: type:
      let
        base = baseNameOf (toString path);
      in
      !(builtins.elem base forbiddenSourceNames || pkgs.lib.hasPrefix "result-" base);
  };
in
pkgs.runCommand "hermes-math-profile-${host}-candidate"
  {
    nativeBuildInputs = [
      python
      pkgs.makeWrapper
    ];
  }
  ''
    mkdir source
    cp -R ${bundleSource} source/bundle
    cp ${../profile-registry.json} source/profile-registry.json
    chmod -R u+w source
    python source/bundle/scripts/refresh_manifest.py
    mkdir -p "$out/profile" "$out/bin" "$TMPDIR/math-fixture"
    printf '%s\n' fixture-only > "$TMPDIR/math-fixture/.math-parity-fixture"
    python source/bundle/scripts/build_candidate.py \
      --host ${host} \
      --output "$out/profile"
    python source/bundle/scripts/run_behavior_parity.py \
      --fixture source/bundle/behavior-fixture.json \
      --self-test > "$out/behavior-harness-self-test.json"
    python source/bundle/scripts/math_profile_materialize.py \
      --candidate "$out/profile" \
      --profile-root "$TMPDIR/math-fixture" > "$out/materialization-plan.json"
    mkdir -p "$out/libexec"
    install -m 0644 source/bundle/scripts/math_profile_materialize.py \
      "$out/libexec/math_profile_materialize.py"
    install -m 0644 source/bundle/scripts/run_behavior_parity.py \
      "$out/libexec/run_behavior_parity.py"
    makeWrapper ${python}/bin/python "$out/bin/math-profile-materialize" \
      --add-flags "$out/libexec/math_profile_materialize.py"
    makeWrapper ${python}/bin/python "$out/bin/math-profile-behavior-parity" \
      --add-flags "$out/libexec/run_behavior_parity.py"
    test ! -e "$TMPDIR/math-fixture/SOUL.md"
  ''
