return {
	{
		"navarasu/onedark.nvim",
		config = function()
			require("onedark").setup({
				style = "dark",
				highlights = {
					["@markup.heading.1.markdown"] = { fg = "$cyan", fmt = "bold" },
					["@markup.heading.1.marker.markdown"] = { fg = "$cyan", fmt = "bold" },
				},
			})
		end,
		-- config = function()
		-- 	local c = require('onedark.colors')
		-- 	require('onedark').setup({
		-- 		highlights = {
		-- 			["@markup.heading.1.markdown"] = { fg = c.cyan, fmt = "bold" },
		-- 		},
		-- 	})
		-- end
	},
}
