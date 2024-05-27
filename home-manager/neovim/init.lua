local lazypath = "@lazy_nvim@";
vim.opt.rtp:prepend(lazypath)

require("options")
require("keymaps")
require("lazy").setup("plugins")
vim.cmd [[colorscheme tokyonight]]

require'lspconfig'.lua_ls.setup{}

local cmp = require'cmp'
require'cmp'.setup {
  sources = {
	{ name = 'nvim_lsp' },
	{ name = 'buffer' },
  },
}

local capabilities = require('cmp_nvim_lsp').update_capabilities(vim.lsp.protocol.make_client_capabilities())
local lsp_attach = function(client, buf)
	vim.api.nvim_buf_set_option(buf, "formatexpr", "v:lua.vim.lsp.formatexpr()")
	vim.api.nvim_buf_set_option(buf, "omnifunc", "v:lua.vim.lsp.omnifunc")
	vim.api.nvim_buf_set_option(buf, "tagfunc", "v:lua.vim.lsp.tagfunc")
end

require("rust-tools").setup({
	server = {
		capabilities = capabilities,
		on_attach = lsp_attach,
	},
})
require'lspconfig'.lua_ls.setup{}

