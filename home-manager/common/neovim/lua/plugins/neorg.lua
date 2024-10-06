return
{
	{
		name = "neorg",
		dir = "@neorg@",
		-- "nvim-neorg/neorg",
		lazy = false,
		version = "*",
		dependencies = {
			{
				"vhyrro/luarocks.nvim",
				opts = {
					luarocks_build_args = {
						"--with-lua-include=/nix/store/r627zxpfnw1ghzr3fykpxlnhjx1gsycv-luajit-2.1-20220915/include",
					},
				},
			},
		},
		config = function()
			require("neorg").setup {
				load = {
					["core.defaults"] = {},
					["core.concealer"] = {
						config = {
							icons = {
								todo = {
									done = {
										icon = "󰄬",
									},
									on_hold = {
										icon = "",
									},
								},
							},
						},
					},
					["core.dirman"] = {
						config = {
							workspaces = {
								notes = "~/notes",
							},
							default_workspace = "notes",
						},
					},
					["core.completion"] = {
						config = {
							engine = "nvim-cmp",
						},
					},
					["core.integrations.nvim-cmp"] = {},

				},
			}
			vim.wo.foldlevel = 99
			vim.wo.conceallevel = 2
		end,
	},
}
