return {
	{
		name = "telescope.nvim",
		dir = "@telescope_nvim@",
		dependencies = {
			{
				name = "plenary.nvim",
				dir = "@plenary_nvim@",
			},
			{
				name = "telescope-fzf-native.nvim",
				dir = "@telescope_fzf_native_nvim@",
				build = 'make',
			},
		},
		config = function()
			telescope = require('telescope')
			require('telescope').setup {
				defaults = {
					mappings = {
						i = {
							["<C-J>"] = { "<Plug>(skkeleton-enable)", type = "command" },
							["<C-L>"] = { "<Plug>(skkeleton-disable)", type = "command" },
						},
					}
				},
				extensions = {
					fzf = {
						fuzzy = true,
						override_generic_sorter = true,
						override_file_sorter = true,
						case_mode = "smart_case",
					},
				},
			}
			require('telescope').load_extension('fzf')
			local builtin = require('telescope.builtin')
			vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Telecope find files' })
			vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = 'Telecope live grep' })
			vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Telecope buffers' })
			vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Telecope help tags' })
		end,
	},
	{
		name = "telescope-file-browser.nvim",
		dir = "@telescope_file_browser_nvim@",
	},
}
