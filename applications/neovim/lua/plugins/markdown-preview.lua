return {
	{
		name = "markdown-preview.nvim",
		dir = "@markdown_preview_nvim@",
		ft = { "markdown" },
		config = function()
			vim.g.mkdp_theme = "light"
			vim.g.mkdp_auto_start = 1
		end,
	},
}
