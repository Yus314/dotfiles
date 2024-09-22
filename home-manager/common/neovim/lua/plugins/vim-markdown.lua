return {
	{
		name = "vim-markdown",
		dir = "@vim_markdown@",
		ft = { "md" },
		config = function()
			vim.g.vim_markdown_folding_disabled = 1
		end
	},
}
