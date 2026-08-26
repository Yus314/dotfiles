{
  config,
  lib,
  pkgs,
  ...
}:
let
  lean4_4_30_0 = pkgs.lean4;

  # Keep newer project toolchains reproducible even when the locked nixpkgs
  # revision has not caught up yet.  Reuse the nixpkgs Lean build expression
  # so its platform support and runtime wrapping stay consistent.
  lean4_4_32_1 = pkgs.lean4.overrideAttrs (
    _finalAttrs: previousAttrs: {
      version = "4.32.1";
      buildInputs = previousAttrs.buildInputs ++ [ pkgs.openssl ];
      patches = [ ./mimalloc-4.32.patch ];
      src = pkgs.fetchFromGitHub {
        owner = "leanprover";
        repo = "lean4";
        tag = "v4.32.1";
        hash = "sha256-2P47y6b51dZbnO6Bj1yqXwmR1Qd5veGqqVY8vQCB7KM=";
      };
    }
  );

  # Elan encodes `origin:channel` names when storing toolchains.  Home Manager
  # owns these links, while Elan remains the project-aware dispatcher for each
  # repository's lean-toolchain file.
  toolchains = {
    "leanprover--lean4---v4.30.0" = lean4_4_30_0;
    "leanprover--lean4---v4.32.1" = lean4_4_32_1;
  };
in
{
  assertions = [
    {
      assertion = lean4_4_30_0.version == "4.30.0";
      message = "The pinned nixpkgs Lean version changed; update the declarative Lean toolchains.";
    }
  ];

  home.packages = [ pkgs.elan ];

  xdg.dataFile = lib.mapAttrs' (
    name: source:
    lib.nameValuePair "elan/toolchains/${name}" {
      inherit source;
    }
  ) toolchains;
}
