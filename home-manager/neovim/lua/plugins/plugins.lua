return {
	{
		name = "barbar.nvim",
		dir = "@barbar_nvim@",
	},
	{
		-- 自動でフォーマットするためだけに入れているが他に良い方法があるかも
		name = "conform-nvim",
		dir = "@conform_nvim@",
		opts = {
			format_on_save = {
				timeout = 500,
				lsp_fallback = true,
			},
		},
	},
	{
		-- 何故か Python はこれがないとformat できない。
		name = "null-ls.nvim",
		dir = "@null_ls_nvim@",
		config = function()
			local null_ls = require("null-ls")
			null_ls.setup({
				sources = {
					null_ls.builtins.formatting.black,
					null_ls.builtins.formatting.isort,
					null_ls.builtins.formatting.nixfmt,
				},
			})
		end,
	},
	{
		"epwalsh/obsidian.nvim",
		opts = {
			workspaces = {
				{
					name = "obsidian",
					path = "~/obsidian",
				},
			},
		},
	},
	{
		name = "rust-tools.nvim",
		dir = "@rust_tools_nvim@",
	},
	{
		name = "markdown-preview.nvim",
		dir = "@markdown_preview_nvim@",
	},
	{
		name = "lualie.nvim",
		dir = "@lualine_nvim@",
		dependencies = { {
			name = "nvim-web-devicons",
			dir = "@nvim_web_devicons@",
		} }
	},
	{
		name = "toggleterm.nvim",
		dir = "@toggleterm_nvim@",
		opts = {
			direction = "float",
			float_opts = {
				border = "curved",
				winblend = 30,
			},
		},
	},
	{
		name = "tokyonight.nvim",
		dir = "@tokyonight_nvim@",
		lazy = false,
		priority = 1000,
		opts = {
			style = "storm",
		},
	},
	{
		name = "telescope.nvim",
		dir = "@telescope_nvim@",
		dependencies = {
			{
				name = "plenary.nvim",
				dir = "@plenary_nvim@",
			},
		},
	},
	{
		name = "telescope-file-browser.nvim",
		dir = "@telescope_file_browser_nvim@",
	},
	{
		name = "noice.nvim",
		dir = "@noice_nvim@",
		opts = {
			cmdline = {
				enabled = true,
			},
		},
		dependencies = {
			{
				name = "nui.nvim",
				dir = "@nui_nvim@",
			},
		},
	},
	{
		name = "copilot.vim",
		dir = "@copilot_vim@",
	},
	{
		name = "nvim-lspconfig",
		dir = "@nvim_lspconfig@",
	},
	{
		name = "nvim-cmp",
		dir = "@nvim_cmp@",
		dependencies = {
			{
				name = "cmp-path",
				dir = "@cmp_path@",
			},
			{
				name = "luasnip",
				dir = "@luasnip@",
			},
			{
				name = "cmp-nvim-lsp",
				dir = "@cmp_nvim_lsp@",
			},
			{
				name = "cmp-buffer",
				dir = "@cmp_buffer@",
			},
		},
	},
}
