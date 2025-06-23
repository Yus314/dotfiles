return {
	{
		name = "lualie.nvim",
		dir = "@lualine_nvim@",
		dependencies = {
			{
				name = "nvim-web-devicons",
				dir = "@nvim_web_devicons@",
			},
		},
		config = function()
			require("lualine").setup({
				options = {
					theme = "onedark",
				},
			})
		end,
	},
}
