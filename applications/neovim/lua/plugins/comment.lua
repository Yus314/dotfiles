return {
	{
		name = "comment-nvim",
		dir = "@comment_nvim@",
		config = function()
			require('Comment').setup()
		end,
		opts = {
			keys = "aoeuidhtns-",
		},
	},
}
