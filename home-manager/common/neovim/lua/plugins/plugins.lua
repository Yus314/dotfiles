return {
	-- {
	-- 	name = "nvim-nu",
	-- 	dir = "@nvim_nu@",
	-- },
	{
		name = "comment-nvim",
		dir = "@comment_nvim@",
		config = function()
			require('Comment').setup()
		end
	},
	{
		name = "dial-nvim",
		dir = "@dial_nvim@",
		config = function()
			local augend = require("dial.augend")
			require("dial.config").augends:register_group {
				default = {
					augend.integer.alias.decimal,
					augend.integer.alias.hex,
					augend.date.alias["%Y/%m/%d"],
					augend.constant.alias.bool,
					augend.constant.new {
						elements = { "and", "or" },
						word = true,
						cyclic = true,
					},
					augend.constant.new {
						elements = { "&&", "||" },
						word = true,
						cyclic = true,
					},
					augend.constant.alias.alpha,
					augend.constant.alias.Alpha,
				}
			}
			vim.keymap.set("n", "<C-a>", function()
				require("dial.map").manipulate("increment", "normal")
			end)
			vim.keymap.set("n", "<C-x>", function()
				require("dial.map").manipulate("decrement", "normal")
			end)
			vim.keymap.set("n", "g<C-a>", function()
				require("dial.map").manipulate("increment", "gnormal")
			end)
			vim.keymap.set("n", "g<C-x>", function()
				require("dial.map").manipulate("decrement", "gnormal")
			end)
			vim.keymap.set("v", "<C-a>", function()
				require("dial.map").manipulate("increment", "visual")
			end)
			vim.keymap.set("v", "<C-x>", function()
				require("dial.map").manipulate("decrement", "visual")
			end)
			vim.keymap.set("v", "g<C-a>", function()
				require("dial.map").manipulate("increment", "gvisual")
			end)
			vim.keymap.set("v", "g<C-x>", function()
				require("dial.map").manipulate("decrement", "gvisual")
			end)
		end
	},
	{
		name = "oil-nvim",
		dir = "@oil_nvim@",
		---@module 'oil'
		---@type oil.SetupOpts
		opts = {},
		-- Optional dependencies
		dependencies = { { "echasnovski/mini.icons", opts = {} } },
		-- dependencies = { "nvim-tree/nvim-web-devicons" }, -- use if prefer nvim-web-devicons
		config = function()
			vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })
			require("oil").setup({
				keymaps = {
					["<C-s>"] = function()
						require("oil").select({ close = true })
						vim.cmd("vsplit")
						vim.cmd("wincmd r")
					end,
				},
			})
		end
	},
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
		'navarasu/onedark.nvim',
		opts = {
			style = 'dark',
		},
	},
	{
		name = "vimtex",
		dir = "@vimtex@",
		config = function()
			vim.g.vimtex_view_method = "zathura"
			--	vim.g.vimtex_view_method = "skim"
		end,
		ft = { "tex" },
	},
	{
		"delphinus/skkeleton_indicator.nvim",
		branch = "main",
		opts = {}
	},
	{
		name = "nvim-treesitter",
		dir = "@nvim_treesitter@",
		build = ":TSUpdate",
		config = function()
			require("nvim-treesitter.configs").setup({
				sync_install = false,
				highlight = {
					enable = true,
				},
				indent = { enable = true },
			})
		end,
		dependencies = {
			{
				"nushell/tree-sitter-nu",
			},
		},
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
		init_options = {
			userLanguages = {
				eelixir = "html-eex",
				eruby = "erb",
				rust = "html",
			},
		},
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
			{
				'rinx/cmp-skkeleton',
			},
		},
	},
}
