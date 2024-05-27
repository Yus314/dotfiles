return {
	{
		name = "barbar.nvim",
		dir = "@barbar_nvim@",
	},
	
	{'hrsh7th/cmp-nvim-lua'},
	{ 'hrsh7th/cmp-nvim-lsp-signature-help'},
	{ 'hrsh7th/cmp-vsnip'                    },         
	{ 'hrsh7th/cmp-path'                       },       
	{ 'hrsh7th/cmp-buffer'                       },     
	 { 'hrsh7th/vim-vsnip'},
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
		dependencies = { 'nvim-tree/nvim-web-devicons' }
	},
	{
		name = "toggleterm.nvim",
		dir = "@toggleterm_nvim@",
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
		name = "nvim-treesitter",
		dir = "@nvim_treesitter@",
	},
	{
		name = "gitsigns.nvim",
		dir = "@gitsigns_nvim@",
		opts = {
			signs                             = {
				add          = { text = '┃' },
				change       = { text = '┃' },
				delete       = { text = '_' },
				topdelete    = { text = '‾' },
				changedelete = { text = '~' },
				untracked    = { text = '┆' },
			},
			signcolumn                        = true, -- Toggle with `:Gitsigns toggle_signs`
			numhl                             = false, -- Toggle with `:Gitsigns toggle_numhl`
			linehl                            = false, -- Toggle with `:Gitsigns toggle_linehl`
			word_diff                         = false, -- Toggle with `:Gitsigns toggle_word_diff`
			watch_gitdir                      = {
				follow_files = true
			},
			attach_to_untracked               = false,
			current_line_blame                = false, -- Toggle with `:Gitsigns toggle_current_line_blame`
			current_line_blame_opts           = {
				virt_text = true,
				virt_text_pos = 'eol', -- 'eol' | 'overlay' | 'right_align'
				delay = 1000,
				ignore_whitespace = false,
				virt_text_priority = 100,
			},
			current_line_blame_formatter      = '<author>, <author_time:%Y-%m-%d> - <summary>',
			current_line_blame_formatter_opts = {
				relative_time = false,
			},
			sign_priority                     = 6,
			update_debounce                   = 100,
			status_formatter                  = nil, -- Use default
			max_file_length                   = 40000, -- Disable if file is longer than this (in lines)
			preview_config                    = {
				-- Options passed to nvim_open_win
				border = 'single',
				style = 'minimal',
				relative = 'cursor',
				row = 0,
				col = 1
			},
		},
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
		"neovim/nvim-lspconfig"
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
