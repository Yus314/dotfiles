return {
	{
		name = "copilot.vim",
		dir = "@copilot_vim@",
		config = function()
			vim.g.copilot_filetypes = {
				markdown = false,
			}
		end,
	},
}
