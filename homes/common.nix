{
  pkgs,
  ...
}:
{
  programs.home-manager.enable = true;
  home = {
    stateVersion = "25.05";
  };
  imports = [
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
  ];
  services.gpg-agent = {
    enable = true;
    defaultCacheTtl = 60 * 60 * 24;
    defaultCacheTtlSsh = 60 * 60 * 24;
    maxCacheTtl = 60 * 60 * 24;
    maxCacheTtlSsh = 60 * 60 * 24;
    enableSshSupport = true;
    enableExtraSocket = true;
    pinentry.package = pkgs.pinentry-tty;
  };

  programs.fish = {
    interactiveShellInit = ''
      set -x SSH_AUTH_SOCK $(gpgconf --list-dirs agent-ssh-socket)
    '';
  };
}
