local capabilities = require('cmp_nvim_lsp').default_capabilities(vim.lsp.protocol.make_client_capabilities())
local lsp_attach = function(client, buf)
	vim.api.nvim_buf_set_option(buf, "formatexpr", "v:lua.vim.lsp.formatexpr()")
	vim.api.nvim_buf_set_option(buf, "omnifunc", "v:lua.vim.lsp.omnifunc")
	vim.api.nvim_buf_set_option(buf, "tagfunc", "v:lua.vim.lsp.tagfunc")
end

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
require 'lspconfig'.pylsp.setup({
	capabilities = capabilities,
	on_attach = lsp_attach,
	settings = {
		pylsp = {
			plugins = {
				flake8 = {
					enabled = true,
				},
				black = {
					enabled = true,
				},
				isort = {
					enabled = true,
				},
			},
		},
	},
})
