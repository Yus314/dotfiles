return {
	{
		name = "hop-nvim",
		dir = "@hop_nvim@",
		config = function()
			vim.keymap.set("n", "h", "<CMD>HopWord<CR>", { desc = "Hop Word" })
			require("hop").setup({ keys = "k,p.=aoeuidhtns-gcrm" })
		end,
	},
}
