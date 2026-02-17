return {
	name = "kitty-scrollback.nvim",
	dir = "@kitty_scrollback_nvim@",
	enabled = true,
	lazy = true,
	cmd = {
		"KittyScrollbackGenerateKittens",
		"KittyScrollbackCheckHealth",
	},
	event = { "User KittyScrollbackLaunch" },
	config = function()
		require("kitty-scrollback").setup()
	end,
}
