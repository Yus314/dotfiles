return {
	{
		--	 何故か Python はこれがないとformat できない。
		name = "null-ls.nvim",
		dir = "@null_ls_nvim@",
		config = function()
			local null_ls = require("null-ls")
			null_ls.setup({
				sources = {
					null_ls.builtins.formatting.nixfmt,
				},
			})
		end,
	},
}
