local lazypath = "@lazy_nvim@"
vim.opt.rtp:prepend(lazypath)

require("options")
require("keymaps")

require("lazy").setup({
	spec = "plugins",
})
vim.lsp.set_log_level("debug")

require("color")
require("nvim-cmp")
require("lsp")

vim.api.nvim_exec(
	[[
  augroup auto_push
    autocmd!
    autocmd VimLeavePre ~/obsidian/*.md lua AutoPush()
  augroup END
]],
	false
)

function AutoPull()
	local project_dir = "/Users/kakinumayuusuke/obsidian"
	if vim.fn.isdirectory(project_dir) == 1 then
		--vim.cmd('silent !bash ' .. project_dir .. '/auto_pull.sh')
		vim.cmd("silent !cd " .. project_dir .. " && git pull ")
	end
end

function AutoPush()
	local project_dir = "/Users/kakinumayuusuke/obsidian"
	if vim.fn.isdirectory(project_dir) == 1 then
		local commit_message = "Update " .. os.date("%Y-%m-%d %H: %M: %S")
		vim.cmd(
			"silent !cd " .. project_dir .. ' && git add .  && git commit -m "' .. commit_message .. '" && git push'
		)
	end
end

vim.api.nvim_exec(
	[[
 augroup auto_pull
  autocmd!
  autocmd BufReadPre ~/obsidian/*.md lua AutoPull()
 augroup END
]],
	false
)

-- 	execute '!open -na "Google Chrome" --args --new-window --app=' . a:url
vim.cmd([[
function OpenMarkdownPreview (url)
    execute "! vivaldi --args --new-window --app= " . a:url
endfunction
]])
vim.g.mkdp_browserfunc = "OpenMarkdownPreview"

local Terminal = require("toggleterm.terminal").Terminal

local cargo_run = Terminal:new({
	cmd = "cargo run",
	hiddcen = true, -- 通常のToggleTermコマンドでは開かれない
	close_on_exit = false,
})

function _cargo_run_toggle()
	cargo_run:toggle() -- ターミナルを開く/閉じる
end

vim.api.nvim_set_keymap("n", "<leader>r", "<cmd>lua _cargo_run_toggle()<CR>", { noremap = true, silent = true })

function _cargo_test_toggle()
	local cargo_test = Terminal:new({
		cmd = "cargo compete t " .. vim.fn.expand("%:t:r"),
		hidden = true, -- 通常のToggleTermコマンドでは開かれない
		close_on_exit = false,
	})
	cargo_test:toggle() -- ターミナルを開く/閉じる
end

vim.api.nvim_create_autocmd("FileType", {
	pattern = { "*.rs" },
	callback = function()
		vim.schedule(function()
			vim.api.nvim_set_keymap(
				"n",
				"<leader>t",
				"<cmd>lua _cargo_test_toggle()<CR>",
				{ noremap = true, silent = true }
			)
		end)
	end,
})

function _cargo_submit_toggle()
	local cargo_submit = Terminal:new({
		cmd = "cargo compete submit " .. vim.fn.expand("%:t:r"),
		hidden = true, -- 通常のToggleTermコマンドでは開かれない
		close_on_exit = false,
	})
	cargo_submit:toggle() -- ターミナルを開く/閉じる
end

vim.api.nvim_set_keymap("n", "<leader>s", "<cmd>lua _cargo_submit_toggle()<CR>", { noremap = true, silent = true })

local lazygit = Terminal:new({
	cmd = "lazygit",
	hidden = true, -- 通常のToggleTermコマンドでは開かれない
})

function _lazygit_toggle()
	lazygit:toggle()
end

vim.api.nvim_set_keymap("n", "<leader>g", "<cmd>lua _lazygit_toggle()<CR>", { noremap = true, silent = true })
