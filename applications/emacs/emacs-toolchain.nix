{ inputs, system }:
import inputs.nixpkgs-emacs {
  inherit system;
  config.allowUnfree = true;
  overlays = [
    inputs.emacs-overlay-31.overlays.default
    (final: prev: {
      # emacs-overlay-31 pins the official emacs-31.0.90 tag, which predates
      # the clean 94ee683 baseline.  The exact 94ee683..60b9161 cumulative
      # diff applies cleanly (with line offsets only) and preserves both the
      # physical-extra-cursor prototype and its explicit-state refactor.
      emacs-unstable-pgtk = prev.emacs-unstable-pgtk.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ./patches/emacs-31-physical-extra-cursors-explicit-state.patch
        ];
      });
    })
    inputs.nur-packages.overlays.default
  ];
}
