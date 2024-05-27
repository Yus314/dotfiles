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
	pkgs.python311Packages.python-lsp-server
	pkgs.python311Packages.flake8
	pkgs.python311Packages.black
	pkgs.python310Packages.isort
	pkgs.rustfmt
	];
  };
}
