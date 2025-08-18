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
    stateVersion = "25.05";
  };
  imports = [
    sops-nix.homeManagerModules.sops
    ../modules/home-manager
    ../applications/emacs
    ../applications/emacs/service.nix
    ../applications/fish
    ../applications/git
    ../applications/lazygit
    ../applications/misc
    ../applications/neomutt
    ../applications/neovim
    ../applications/nushell
    ../applications/offlineimap
    ../applications/wezterm
    ../applications/zsh
    ../applications/ssh
    ../applications/gh
    ../applications/gnupg
    ../applications/bash
    ../applications/less
    ../applications/claude-code
    ../applications/mcp
    ../applications/vim
    ../applications/rbw
    ../applications/tf-wrapper
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
