return {
	{
		name = "nvim-cmp",
		dir = "@nvim_cmp@",
		dependencies = {
			{
				name = "cmp-path",
				dir = "@cmp_path@",
			},
			{
				name = "luasnip",
				dir = "@luasnip@",
			},
			{
				name = "cmp-nvim-lsp",
				dir = "@cmp_nvim_lsp@",
			},
			{
				name = "cmp-buffer",
				dir = "@cmp_buffer@",
			},
			{
				'rinx/cmp-skkeleton',
			},

		},
		config = function()
			local cmp = require("cmp")
			cmp.setup({
				sources = cmp.config.sources({
					{ name = 'neorg' },
				}),
			})
		end
	},
	{
		"delphinus/skkeleton_indicator.nvim",
		branch = "main",
		opts = {}
	},
}
