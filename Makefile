# Variables
HOST := $(shell uname -n)
SYSTEM := $(if $(filter Darwin,$(shell uname -s)),aarch64-darwin,x86_64-linux)
NIX_PROFILE := /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
NIX := $(or $(NIX),nom)

# Phony targets
.PHONY: build build-all x86_64-linux aarch64-darwin install_nix uninstall_nix

# Default target
build: $(SYSTEM) ## 現在のシステム向けのNix Configurationをビルドします

build-all: x86_64-linux aarch64-darwin ## 全てのシステムのNix Configurationをビルドします

x86_64-linux: ## 全てのLinux (x86_64) ホスト向けのビルド
	$(NIX) build --impure --keep-going --no-link --show-trace --system x86_64-linux \
		.#nixosConfigurations.lawliet.config.system.build.toplevel \
		.#nixosConfigurations.ryuk.config.system.build.toplevel \
		.#nixosConfigurations.rem.config.system.build.toplevel

aarch64-darwin: ## macOS (aarch64) 向けのビルド
	$(NIX) build --keep-going --no-link --show-trace --system aarch64-darwin --option extra-sandbox-paths /nix/store \
		.#darwinConfigurations.watari.system

install_nix: ## Determinate Systemsのインストーラを使ってNixをインストールします
	@if [ ! -f "$(NIX_PROFILE)" ]; then \
		curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install; \
	else \
		echo "Nix is already installed"; \
	fi

uninstall_nix: ## Nixをアンインストールします
	/nix/nix-installer uninstall