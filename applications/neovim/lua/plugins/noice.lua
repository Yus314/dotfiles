return {
	{
		name = "noice.nvim",
		dir = "@noice_nvim@",
		opts = {
			cmdline = {
				enabled = true,
			},
		},
		dependencies = {
			{
				name = "nui.nvim",
				dir = "@nui_nvim@",
			},
		},
	},
}
