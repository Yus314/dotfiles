{
  config,
  pkgs,
  inputs,
  ...
}: let
  un =
    if pkgs.stdenv.isDarwin
    then "kakinumayuusuke"
    else "kaki";
  hd =
    if pkgs.stdenv.isDarwin
    then "/Users/"
    else "/home/";
    plugins = import ./neovim/plugins.nix { inherit pkgs; };
    initLua = pkgs.substituteAll ( {
    	src = ./neovim/init.lua;
	#barbar_nvim = pkgs.vimPlugins.barbar-nvim;

	} // plugins );
    pluginsLua = pkgs.substituteAll ( {
    	src = ./neovim/lua/plugins.lua;
	#barbar_nvim = pkgs.vimPlugins.barbar-nvim;

	} // plugins );

in {
  home = rec {
    username = un;
    homeDirectory = hd + un;
    stateVersion = "23.11";
    packages = with pkgs; [
      cowsay
      bat
      eza
      tldr
      alejandra
      nodePackages.prettier
      obsidian
    ];
  };
  imports = [
    inputs.nixvim.homeManagerModules.nixvim
    #./neovim/neovim.nix
    ./zsh.nix
    ./alacritty.nix
    ./git.nix
    ./neovim/neovim.nix
  ];
  programs.gh = {
    enable = true;
  };
  programs.lazygit = {
    enable = true;
  };
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };
  programs.fzf = {
    enable = true;
  };
  xdg.configFile= {
  ## "nvim/init.lua".source = ./neovim/init.lua;
  "nvim/init.lua".source = initLua;
  "nvim/lua/plugins.lua".source = pluginsLua;
  "nvim/lua/options.lua".source = ./neovim/lua/options.lua;
  "nvim/lua/keymaps.lua".source = ./neovim/lua/keymaps.lua;
  };

  #programs.vivaldi = {
  #enable = true;
  #};
  programs.home-manager.enable = true;
}
