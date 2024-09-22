return {
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
}
