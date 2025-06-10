return {
	{
		name = "nvim-treesitter",
		dir = "@nvim_treesitter@",
		build = ":TSUpdate",
		config = function()
			require("nvim-treesitter.configs").setup({
				sync_install = false,
				highlight = {
					enable = true,
				},
				indent = { enable = true },
			})
		end,
	},
}
