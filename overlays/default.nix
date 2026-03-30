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

  fcitx5-updated = final: prev: {
    fcitx5 = prev.fcitx5.overrideAttrs (oldAttrs: rec {
      version = "5.1.14";
      src = prev.fetchFromGitHub {
        owner = "fcitx";
        repo = "fcitx5";
        rev = version;
        hash = "sha256-wLJZyoWjf02+m8Kw+IcfbZY2NnjMGtCWur2+w141eS4=";
      };
    });
  };
}
