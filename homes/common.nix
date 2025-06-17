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
  ];
}
