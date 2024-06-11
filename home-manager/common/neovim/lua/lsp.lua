local capabilities = require('cmp_nvim_lsp').default_capabilities(vim.lsp.protocol.make_client_capabilities())
local lsp_attach = function(client, buf)
	vim.api.nvim_buf_set_option(buf, "formatexpr", "v:lua.vim.lsp.formatexpr()")
	vim.api.nvim_buf_set_option(buf, "omnifunc", "v:lua.vim.lsp.omnifunc")
	vim.api.nvim_buf_set_option(buf, "tagfunc", "v:lua.vim.lsp.tagfunc")
end


vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, opts)
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, opts)
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, opts)

vim.keymap.set('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<CR>')
vim.keymap.set('n', 'gr', '<cmd>lua vim.lsp.buf.references()<CR>')
vim.keymap.set('n', 'gD', '<cmd>lua vim.lsp.buf.declaration()<CR>')
vim.keymap.set('n', 'gI', '<cmd>lua vim.lsp.buf.implementation()<CR>')
vim.keymap.set('n', 'gT', '<cmd>lua vim.lsp.buf.type_definition()<CR>')
vim.keymap.set('n', 'K', '<cmd>lua vim.lsp.buf.hover()<CR>')
vim.keymap.set('n', '<leader>cw', '<cmd>lua vim.lsp.buf.workspace_symbol()<CR>')
vim.keymap.set('n', '<leader>cr', '<cmd>lua vim.lsp.buf.rename()<CR>')
vim.keymap.set('n', 'gf', '<cmd>lua vim.lsp.buf.format()<CR>')




require("rust-tools").setup({
	server = {
		capabilities = capabilities,
		on_attach = lsp_attach,
		settings = {
			["rust-analyzer"] = {
				checkOnSave = {
					allFeatures = true,
					command = "clippy",
				},
			},
		},
	},
})
require 'lspconfig'.lua_ls.setup {}
require 'lspconfig'.texlab.setup {}
require 'lspconfig'.pylsp.setup({
	capabilities = capabilities,
	on_attach = lsp_attach,
	settings = {
		pylsp = {
			plugins = {
				flake8 = {
					enabled = true,
					ignore = { 'E203', },
					maxLineLength = 119,
				},
				black = {
					enabled = true,
					lineLength = 119,
				},
				isort = {
					enabled = true,
				},
			},
		},
	},
})
require 'lspconfig'.nil_ls.setup {
	autostart = true,
	capabilities = capabilities,
	on_attach = lsp_attach,
	formatting = {
		command = "nixfmt",
	},
}
