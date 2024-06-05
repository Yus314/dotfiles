local cmp = require 'cmp'
require 'cmp'.setup {
	snippet = {
		expand = function(args)
			require('luasnip').lsp_expand(args.body)
		end,
	},
	mapping = {
		['<CR>'] = cmp.mapping.confirm({ select = true }),
	},
	sources = {
		{ name = 'nvim_lsp' },
		{ name = 'path' },
		{ name = 'buffer' },
		{ name = 'skkeleton' },
	},
}
