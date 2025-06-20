.PHONY: install_nix uninstall_nix build build-all x86_64-linux  aarch64-darwin

UNAME := $(shell uname)
NIX_PROFILE := /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

NIX := nom

OS := $(shell uname -s)
ARCH := $(shell uname -m)

JOBS_X86_64-LINUX :=
JOBS_AARCH64-DARWIN :=

