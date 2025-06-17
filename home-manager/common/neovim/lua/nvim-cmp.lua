local cmp = require("cmp")
require("cmp").setup({
	snippet = {
		expand = function(args)
			require("luasnip").lsp_expand(args.body)
		end,
	},
	mapping = {
		["<CR>"] = cmp.mapping.confirm({ select = true }),
		["<C-h>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
		["<C-t>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
	},
	sources = {
		{ name = "nvim_lsp" },
		{ name = "path" },
		{ name = "buffer" },
		{ name = "skkeleton" },
	},
})
