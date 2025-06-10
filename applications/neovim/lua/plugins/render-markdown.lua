return {
	{
		'MeanderingProgrammer/render-markdown.nvim',
		opts = {},
		ft = 'markdown',
		dependencies = {
			{
				name = 'nvim-treesitter',
				dir = '@nvim_treesitter@',
			},
			{
				name = 'nvim-web-devicons',
				dir = '@nvim_web_devicons@',
			},
		},
		config = function()
			require('render-markdown').setup({
				heading = {
					backgrounds = {
						'RenderMarkdownCode',
						'RenderMarkdownCode',
						'RenderMarkdownCode',
						'RenderMarkdownCode',
						'RenderMarkdownCode',
						'RenderMarkdownCode',
					},
					foregrounds = {
						'RenderMarkdownH1',
						'RenderMarkdownH2',
						'RenderMarkdownH3',
						'RenderMarkdownH4',
						'RenderMarkdownH5',
						'RenderMarkdownH6',
					},
				},
			})
			vim.g.conceallevel = 2
		end,
	},
}
