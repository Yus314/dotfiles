{
  inputs,
  pkgs,
  config,
  ...
}:
let
  inherit (inputs) sops-nix;
in
{
  programs.home-manager.enable = true;
  home = {
    stateVersion = "26.05";
  };
  imports = [
    sops-nix.homeManagerModules.sops
    ../modules/home-manager
    ../applications/codex
    ../applications/emacs
    ../applications/emacs/service.nix
    ../applications/fish
    ../applications/git
    ../applications/lazygit
    ../applications/ledger
    ../applications/kakoune
    ../applications/misc
    ../applications/zathura
    ../applications/neomutt
    ../applications/neovim
    ../applications/offlineimap
    ../applications/zsh
    ../applications/ssh
    ../applications/tmux
    ../applications/gh
    ../applications/gnupg
    ../applications/bat
    ../applications/bash
    ../applications/less
    ../applications/claude-code
    ../applications/rbw
    ../applications/sprout
    ../applications/tf-wrapper
    ../applications/nh
    ../applications/vdirsyncer
    ../applications/weekly-report
    #../applications/khal
    #../applications/khalorg
    #../applications/sdcv
  ];
  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 60 * 60 * 24;
    defaultCacheTtlSsh = 60 * 60 * 24;
    maxCacheTtl = 60 * 60 * 24;
    maxCacheTtlSsh = 60 * 60 * 24;
    enableSshSupport = true;
    enableExtraSocket = true;
    extraConfig = ''
      allow-emacs-pinentry
      allow-loopback-pinentry
    '';
  };

  sops.age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt";
  home.preferXdgDirectories = true;

  programs.fish = {
    interactiveShellInit = ''
      set -x SSH_AUTH_SOCK $(gpgconf --list-dirs agent-ssh-socket)
    '';
  };
}
