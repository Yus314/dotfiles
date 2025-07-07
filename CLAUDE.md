# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a NixOS/Nix-Darwin dotfiles repository using Nix Flakes with a modular configuration structure. The repository manages system configurations for multiple hosts across Linux (NixOS) and macOS (Darwin) systems.

### Key Configuration Structure

- **flake.nix**: Main flake configuration defining inputs, outputs, and host configurations
- **flake-module.nix**: Custom flake module that dynamically generates system configurations from the `hosts` attribute set
- **Taskfile.yml**: Task runner configuration for common operations
- **hosts** definition in flake.nix maps to actual system configurations:
  - `watari`: x86_64-linux desktop system
  - `lawliet`: aarch64-darwin (macOS) system  
  - `ryuk`: x86_64-linux lab-main system
  - `rem`: x86_64-linux lab-sub system

### Directory Structure

- `applications/`: Application-specific configurations (emacs, neovim, git, etc.)
- `homes/`: Home Manager configurations split by platform (darwin/nixos) and common configs
- `systems/`: System-level configurations split by platform (darwin/nixos) and host-specific configs
- `modules/`: Reusable modules for home-manager, darwin, and nix configurations
- `pkgs/`: Custom package definitions
- `overlays/`: Nixpkgs overlays
- `secrets/`: SOPS-encrypted secrets
- `infra/`: Infrastructure as code (Terraform configurations for Cloudflare, GitHub)

### Configuration Hierarchy

1. **System level**: `systems/{platform}/common.nix` → `systems/{platform}/{hostname}/`
2. **Home Manager level**: `homes/common.nix` → `homes/{platform}/common.nix` → `homes/{platform}/{hostname}/`
3. **Applications**: Individual application configs in `applications/` imported by home configurations

## Common Commands

### Building Configurations

```bash
# Build current system configuration
task build

# Build all system configurations  
task build-all

# Build specific platforms
task linux    # Build x86_64-linux systems
task darwin   # Build aarch64-darwin systems
```

### System Management

```bash
# Switch system configuration (macOS)
task switch

# Install Nix (if not present)
task install_nix

# Uninstall Nix
task uninstal_nix
```

### Development

```bash
# Enter development shell with tools
nix develop

# Format code
nix fmt

# Run pre-commit hooks
nix flake check
```

### Direct Nix Commands

```bash
# Build specific host configurations
nom build .#nixosConfigurations.watari.config.system.build.toplevel
nom build .#darwinConfigurations.lawliet.system

# Build and test without switching
sudo nixos-rebuild build --flake .#watari
darwin-rebuild build --flake .#lawliet
```

## Key Technologies

- **Nix Flakes**: Declarative system configuration with locked dependencies
- **Home Manager**: User environment and dotfiles management
- **SOPS**: Secrets management with age/gpg encryption
- **flake-parts**: Modular flake organization
- **treefmt-nix**: Code formatting with multiple formatters (nixfmt, biome, shfmt, etc.)
- **git-hooks.nix**: Pre-commit hooks integration

## Host-Specific Notes

- **Default username**: `kaki` across all systems
- **Fish shell**: Primary shell configured across all hosts
- **GPG/SSH**: GPG agent configured for SSH authentication
- **Input methods**: fcitx5 with SKK/Mozc for Japanese input (Linux only)
- **Distributed builds**: Configured for cross-platform building (see buildMachines.nix)

## Secrets Management

Secrets are managed using SOPS with age encryption. Key files:
- `secrets/default.yaml`: Main secrets file
- Age key location: `/home/kaki/.config/sops/age/keys.txt` (Linux)
- GPG home for Darwin: `${config.xdg.dataHome}/.gnupg`

## Code Quality and Formatting

This repository uses pre-commit hooks for automated code formatting and quality checks:

- **Automatic formatting**: Files are automatically formatted on commit using treefmt-nix
- **Pre-commit integration**: git-hooks.nix ensures code quality before commits
- **CI/CD validation**: GitHub Actions runs checks and builds on all changes

When committing changes, pre-commit hooks may automatically format files. If this happens:
1. The formatted changes will be applied automatically
2. Accept these formatting changes as they maintain code consistency
3. The commit will proceed with the formatted code