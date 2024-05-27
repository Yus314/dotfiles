{pkgs,... }:{
  programs.neovim = {
    enable = true;
    vimAlias = true;
    extraPackages = with pkgs.vimPlugins; [
	barbar-nvim
	lazy-nvim
	lualine-nvim
	toggleterm-nvim
	tokyonight-nvim
	nvim-ts-autotag
	]
	 ++[
	pkgs.lua-language-server
	pkgs.rust-analyzer
	];
  };
}
