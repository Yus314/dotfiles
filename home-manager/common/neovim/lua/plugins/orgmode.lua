return {
	{
		name = "orgmode",
		dir = "@orgmode@",
		-- ft = { "org" },
		config = function()
			require('orgmode').setup({
				org_agenda_files = '~/opgfiles/**/*',
				org_default_notes_file = '~/opgfiles/refile.org',
				org_capture_templates = {
					m = {
						description = "メモ",
						template = "* %? %U \n",
						target = "~/Dropbox/inbox.org",
					},
					l = {
						description = "研究ノート",
						template = "* %? %U \n",
						target = "~/Dropbox/project/lab.org",
					},
					d = {
						description = "授業",
						template = "* %? %U \n",
						target = "~/Dropbox/project/school.org",
					},
					c = {
						description = "キャリア",
						template = "* %? %U \n",
						target = "~/Dropbox/project/career.org",
					},

					s = {
						description = "スマブラ",
						template = "* %? %U \n",
						target = "~/Dropbox/project/smash.org",
					},

				}
			})
		end,
	},
}
