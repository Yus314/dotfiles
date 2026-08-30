{ pkgs, ... }:
{
  # Keep only the project-aware dispatcher under Nix.  Lean projects pin their
  # upstream toolchain in `lean-toolchain`, and Elan installs that exact release.
  # Nix-built Lean binaries produce `.olean` files with headers that are
  # incompatible with upstream Mathlib caches, forcing a full local rebuild.
  home.packages = [ pkgs.elan ];
}
