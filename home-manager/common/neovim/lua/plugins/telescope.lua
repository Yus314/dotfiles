return {
	{
		name = "telescope.nvim",
		dir = "@telescope_nvim@",
		dependencies = {
			{
				name = "plenary.nvim",
				dir = "@plenary_nvim@",
			},
		},
		config = function()
			require('telescope').load_extension "file_browser"
		end
	},
	{
		name = "telescope-file-browser.nvim",
		dir = "@telescope_file_browser_nvim@",
	},
}
