return {
	{
		name = "vimtex",
		dir = "@vimtex@",
		config = function()
			vim.g.vimtex_view_method = "zathura"
			--	vim.g.vimtex_view_method = "skim"
		end,
		ft = { "tex" },
	},
}
