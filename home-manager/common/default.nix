{
  pkgs,
  emacsPkg,
  org-babel,
  ...
}:
let
  direnv = import ./direnv.nix;
  github = import ./direnv.nix;
  lazygit = import ./lazygit/lazygit.nix;
  alacritty = import ./alacritty.nix;
  fzf = import ./fzf.nix;
  git = import ./git.nix;
  neovim = import ./neovim/neovim.nix;
  tmux = import ./tmux.nix;
  nushell = import ./nushell;
  zsh = import ./zsh;
  zoxide = import ./zoxide.nix;
  bat = import ./bat.nix;
  packages = import ./packages.nix;
  fd = import ./fd.nix;
  ripgrep = import ./ripgrep.nix;
  eza = import ./eza.nix;
  wezterm = import ./wezterm/wezterm.nix;
  fish = import ./fish.nix;
  starship = import ./starship.nix;
  emacs = import ./emacs { inherit pkgs emacsPkg org-babel; };
  neomutt = import ./neomutt.nix;
  offlineimap = import ./offlineimap.nix;
  kitty = import ./kitty.nix;
in
[
  direnv
  github
  lazygit
  alacritty
  fzf
  git
  neovim
  tmux
  nushell
  zsh
  zoxide
  bat
  packages
  fd
  ripgrep
  eza
  wezterm
  fish
  starship
  emacs
  neomutt
  offlineimap
  kitty
]
