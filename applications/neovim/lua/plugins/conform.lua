return {
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
}
