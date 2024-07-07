local opts = { noremap = true, silent = true }
local keymap = vim.api.nvim_set_keymap
keymap("", "<Space>", "<Nop>", opts)
vim.g.mapleader = " "


keymap("n", "<leader>f", "<cmd>Telescope file_browser<CR>", opts)

keymap("n", "[b", "<cmd>BufferPrevious<CR>", opts)
keymap("n", "]b", "<cmd>BufferNext<CR>", opts)
keymap("n", "<C-w>w", "<cmd>BufferClose<CR>", opts)

-- 挿入モードのマッピング
vim.api.nvim_set_keymap('i', '<C-j>', '<Plug>(skkeleton-enable)', { noremap = true, silent = true })


-- コマンドラインモードのマッピング
vim.api.nvim_set_keymap('c', '<C-j>', '<Plug>(skkeleton-enable)', { noremap = true, silent = true })

-- dvorak のための物理的キーマッピングの変更
keymap("n", "d", "h", opts)
keymap("n", "h", "j", opts)
keymap("n", "t", "k", opts)
keymap("n", "n", "l", opts)

-- for visual module
keymap("v", "d", "h", opts)
keymap("v", "h", "j", opts)
keymap("v", "t", "k", opts)
keymap("v", "n", "l", opts)
-- for d key
keymap("n", "e", "d", opts)
keymap("n", "ee", "dd", opts)
