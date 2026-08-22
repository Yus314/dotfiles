{ inputs }:
{
  # Emacs 30.2 + Apple SDK: C23検出によりObjective-Cファイルでbool未定義エラー
  # ref: https://github.com/nix-community/emacs-overlay/issues/519
  emacs-darwin-c23-fix =
    final: prev:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      emacs-unstable = prev.emacs-unstable.overrideAttrs (old: {
        configureFlags = old.configureFlags ++ [ "ac_cv_prog_cc_c23=no" ];
      });
    };

  # direnv: zshテストがDarwinビルドサンドボックス内でchpwdフック時にハング
  # Hydra CIでも間欠的にタイムアウト (aarch64-darwin)
  direnv-darwin-skip-check =
    final: prev:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      direnv = prev.direnv.overrideAttrs (old: {
        doCheck = false;
      });
    };

  kakoune-updated = final: prev: {
    kakoune-unwrapped = prev.kakoune-unwrapped.overrideAttrs (oldAttrs: {
      version = "unstable-2026-05-07";
      src = prev.fetchFromGitHub {
        owner = "mawww";
        repo = "kakoune";
        rev = "0abe83f7cf9a4da3a8d8b1797450ee26f8389459";
        hash = "sha256-LlL5e+AapnG3aWFMVVH9UULIv8b+PWLv+AmRISwXKv8=";
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

}
