{ inputs, system }:
import inputs.nixpkgs-emacs {
  inherit system;
  config.allowUnfree = true;
  overlays = [
    inputs.emacs-overlay-31.overlays.default
    (
      final: prev:
      let
        # emacs-overlay-31 pins the official emacs-31.0.90 tag, which predates
        # the clean 94ee683 baseline.  The exact 94ee683..60b9161 cumulative
        # diff applies cleanly (with line offsets only) and preserves both the
        # physical-extra-cursor prototype and its explicit-state refactor.
        withPhysicalExtraCursors =
          emacs:
          emacs.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [
              ./patches/emacs-31-physical-extra-cursors-explicit-state.patch
            ];
          });
      in
      {
        # Minimal Emacs uses the native NS build on Darwin and PGTK elsewhere.
        emacs-unstable = withPhysicalExtraCursors prev.emacs-unstable;
        emacs-unstable-pgtk = withPhysicalExtraCursors prev.emacs-unstable-pgtk;
      }
    )
    inputs.nur-packages.overlays.default
  ];
}
