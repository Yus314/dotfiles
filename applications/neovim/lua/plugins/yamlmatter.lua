return {
	{
		"ray-x/yamlmatter.nvim",
		config = function()
			require("yamlmatter").setup({
				icon_mappings = {
					uuid = "󰻾",
					updated = "󰚰",
					draft = "",
				},
			})
		end
	},
}
