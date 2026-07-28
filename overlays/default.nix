{ inputs }:
{
  kakoune-updated = final: prev: {
    kakoune-unwrapped = prev.kakoune-unwrapped.overrideAttrs (oldAttrs: {
      version = "unstable-2026-03-25";
      src = prev.fetchFromGitHub {
        owner = "mawww";
        repo = "kakoune";
        rev = "1355294ef3c5deac37e3cdd9a124fe3002e2751a";
        hash = "sha256-H6OJAg7etnriofRDdygMErXQFdUuKBrGpO6Wnz/Usd0=";
      };
    });
  };

  kakoune-lsp-local = final: prev: {
    kakoune-lsp = prev.kakoune-lsp.overrideAttrs (oldAttrs: {
      version = "19.0.1-snapshot-local";
      src = inputs.kakoune-lsp-src;
      cargoDeps = prev.rustPlatform.importCargoLock {
        lockFile = "${inputs.kakoune-lsp-src}/Cargo.lock";
      };
    });
  };

  # nixos-unstable 2026-07-11 predates nixpkgs#536365. Without this,
  # ld64 traps while linking unrelated Darwin packages.
  ld64-unhardened =
    final: prev:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      # Rebuilding the Darwin bootstrap after overriding ld64 exposes GNU tar
      # test 155 (`time: tricky time stamps`) failing on GitHub's arm64 runner.
      # Skip that test only; both check and installCheck remain enabled.
      gnutar = prev.gnutar.overrideAttrs (oldAttrs: {
        postPatch = (oldAttrs.postPatch or "") + ''
          substituteInPlace tests/testsuite \
            --replace-fail \
              $'155;time01.at:20;time: tricky time stamps;time time01;\n' \
              ""
        '';
      });
      ld64 = prev.ld64.overrideAttrs (oldAttrs: {
        hardeningDisable = (oldAttrs.hardeningDisable or [ ]) ++ [ "libcxxhardeningfast" ];
      });
    };

}
