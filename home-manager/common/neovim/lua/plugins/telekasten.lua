return {
	{
		-- name = "telekasten-nvim",
		-- dir = "@telekasten_nvim@",
		'nvim-telekasten/telekasten.nvim',
		config = function()
			require('telekasten').setup({
				home = vim.fn.expand("~/OneDrive/zettelkasten/permanent"),
				templates = vim.fn.expand("~/OneDrive/zettelkasten/permanent/templates"),
				auto_set_filetype = false,
				new_note_filename = "uuid",
				uuid_type = "%Y%m%d%H%M%S",
				tag_notation = "yaml-bare",
				template_new_note = vim.fn.expand("~/OneDrive/zettelkasten/permanent/templates/basenote.md"),
			})

			vim.keymap.set('n', '<leader>ti',
				'<cmd>lua require("telekasten").search_notes({default_text = "title: "})<cr>',
				{ noremap = true, silent = true })
			vim.keymap.set('n', '<leader>nn',
				'<cmd>lua require("telekasten").new_note()<cr>',
				{ noremap = true, silent = true })
			vim.keymap.set('n', '<leader>ta',
				'<cmd>lua require("telekasten").show_tags()<cr>',
				{ noremap = true, silent = true })

			local function update_timestamp_fixed_line()
				local updated_line = "updated: " .. os.date("%Y-%m-%d %H:%M:%S")

				local line_count = vim.api.nvim_buf_line_count(0)
				if line_count >= 5 then
					local line_count = vim.api.nvim_buf_line_count(0)
					vim.api.nvim_buf_set_lines(0, 4, 5, false, { updated_line })
				end
			end
			vim.api.nvim_create_autocmd("BufWritePre", {
				pattern = "/home/kaki/OneDrive/zettelkasten/permanent/*",
				callback = function()
					update_timestamp_fixed_line()
				end,
			})
			-- end,
			-- })
			-- Insert linx をする時にタイトルで検索できるようにする
			function InsertLinks()
				require('telescope.builtin').live_grep({
					prompt_title = "Insert Link",
					cwd = "/home/kaki/OneDrive/zettelkasten/permanent",
					default_text = "title: ",
					attach_mappings = function(_, map)
						map('i', '<CR>', function(prompt_bufnr)
							local content = require('telescope.actions.state').get_selected_entry(prompt_bufnr)
							require('telescope.actions').close(prompt_bufnr)
							vim.api.nvim_put({ "[](" .. content.path .. ")" }, "l", true, true)
						end)
						return true
					end,
				})
			end

			vim.keymap.set('n', '<leader>li', '<cmd>lua InsertLinks()<cr>', { noremap = true, silent = true })
			require('telescope').load_extension "file_browser"
		end,
	},
}
