return {
	{
		"epwalsh/obsidian.nvim",
		opts   = {
			workspaces = {
				{
					name = "obsidian",
					path = "~/obsidian",
				},
			},
		},
		ft     = { "markdown" },
		config = function()
			vim.g.conceallevel = 2
		end
	},
}
