local lazypath = "@lazy_nvim@";
vim.opt.rtp:prepend(lazypath)

require("options")
require("keymaps")



require("lazy").setup({
	spec = {
		{ import = "plugins.plugins" },
		{ import = "plugins.gitsign" },
		{ import = "plugins.markdown-preview" },
	},
})

require("color")
require("nvim-cmp")
require("lsp")
