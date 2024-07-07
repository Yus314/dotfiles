return {
	{
		name = "barbar.nvim",
		dir = "@barbar_nvim@",
	},
	{
		name = "vim-markdown",
		dir = "@vim_markdown@",
		config = function()
			vim.g.vim_markdown_folding_disabled = 1
		end
	},
	{
		name = "vimtex",
		dir = "@vimtex@",
		config = function()
			vim.g.vimtex_view_method = "zathura"
		end
	},
	--{
	--	"vim-skk/skkeleton",
	--	dependencies = {
	--		{
	--			name = "denops.vim",
	--			--dir = "/nix/store/zn4vp6lga0kr7r6nnpl66768i9ajm9wg-vimplugin-denops.vim-2024-04-17",
	--			dir = "@denops_vim@",
	--			--"vim-denops/denops.vim",
	--			config = function()
	--				vim.g['denops#deno'] = '/nix/store/l3adf02p4xdxlvqy5rl2wzb37965nvml-deno-1.43.6/bin/deno'
	--			end
	--		},
	--	},
	--	config = function()
	--		vim.cmd([[
	--		call skkeleton#config({ 'globalDictionaries': ['~/.skk/SKK-JISYO.L'] })
	--		]])
	--	end
	--},
	{
		name = "nvim-treesitter",
		dir = "@nvim_treesitter@",
		build = ":TSUpdate",
		config = function()
			require("nvim-treesitter").setup({
				ensure_installed = { "c", "lua", "vim", "vimdoc", "query", "javascript", "html", "markdown" },
				sync_install = false,
				highlight = { enable = true },
				indent = { enable = true },
			})
		end
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
		opts   = {
			workspaces = {
				{
					name = "obsidian",
					path = "~/obsidian",
				},
			},
		},
		ft     = { "markdown" },
		config = function()
			vim.g.conceallevel = 2
		end
	},
	{
		name = "rust-tools.nvim",
		dir = "@rust_tools_nvim@",
		ft = { "rust" },
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
		config = function()
			require('telescope').load_extension "file_browser"
		end
	},
	{
		name = "telescope-file-browser.nvim",
		dir = "@telescope_file_browser_nvim@",
	},
	--	{
	--		name = "noice.nvim",
	--		dir = "@noice_nvim@",
	--		opts = {
	--			cmdline = {
	--				enabled = true,
	--			},
	--		},
	--		dependencies = {
	--			{
	--				name = "nui.nvim",
	--				dir = "@nui_nvim@",
	--			},
	--		},
	--	},
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
			--{
			--		'rinx/cmp-skkeleton',
			--	},
		},
	},
}
