local lazypath = "@lazy_nvim@";
vim.opt.rtp:prepend(lazypath)

require("options")
require("keymaps")
require("lazy").setup({
	spec = {
		{ import = "plugins.plugins" },
		{ import = "plugins.gitsign" },
	}
})
require("color")
require("nvim-cmp")
require("lsp")


                   local Terminal = require('toggleterm.terminal').Terminal

                   local cargo_run = Terminal:new({
        cmd = "cargo run",
        hiddcen = true, -- 通常のToggleTermコマンドでは開かれない
        close_on_exit = false,
        })

       function _cargo_run_toggle()
       cargo_run:toggle() -- ターミナルを開く/閉じる
       end

       vim.api.nvim_set_keymap("n", "<leader>r", "<cmd>lua _cargo_run_toggle()<CR>", {noremap = true, silent = true})


      local cargo_test = Terminal:new({
        cmd = "cargo compete t " .. vim.fn.expand("%:t:r"),
        hidden = true, -- 通常のToggleTermコマンドでは開かれない
        close_on_exit = false,
        })

       function _cargo_test_toggle()
       cargo_test:toggle() -- ターミナルを開く/閉じる
       end

       vim.api.nvim_set_keymap("n", "<leader>t", "<cmd>lua _cargo_test_toggle()<CR>", {noremap = true, silent = true})

      local cargo_submit = Terminal:new({
        cmd = "cargo compete submit " .. vim.fn.expand("%:t:r"),
        hidden = true, -- 通常のToggleTermコマンドでは開かれない
        close_on_exit = false,
        })

       function _cargo_submit_toggle()
       cargo_submit:toggle() -- ターミナルを開く/閉じる
       end

       vim.api.nvim_set_keymap("n", "<leader>s", "<cmd>lua _cargo_submit_toggle()<CR>", {noremap = true, silent = true})

       local lazygit = Terminal:new({
        cmd = "lazygit",
        hidden = true, -- 通常のToggleTermコマンドでは開かれない
        })

       function _lazygit_toggle()
       lazygit:toggle()
       end

       vim.api.nvim_set_keymap("n", "<leader>g", "<cmd>lua _lazygit_toggle()<CR>", {noremap = true, silent = true})
