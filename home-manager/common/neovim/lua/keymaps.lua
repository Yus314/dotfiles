local opts = { noremap = true, silent = true }
local keymap = vim.api.nvim_set_keymap
keymap("", "<Space>", "<Nop>", opts)
vim.g.mapleader = " "


keymap("n", "<leader>f", "<cmd>Telescope file_browser<CR>", opts)

keymap("n", "[b", "<cmd>BufferPrevious<CR>", opts)
keymap("n", "]b", "<cmd>BufferNext<CR>", opts)
keymap("n", "<C-w>w", "<cmd>BufferClose<CR>", opts)



-- コマンドラインモードのマッピング
vim.api.nvim_set_keymap('c', '<C-j>', '<Plug>(skkeleton-enable)', { noremap = true, silent = true })
vim.api.nvim_set_keymap('c', '<C-l>', '<Plug>(skkeleton-disable)', { noremap = true, silent = true })

-- dvorak のための物理的キーマッピングの変更
keymap("n", "<Right>", "l", opts)
keymap("n", "<Left>", "h", opts)
keymap("n", "<Down>", "j", opts)
keymap("n", "<Up>", "k", opts)

-- for visual module
keymap("v", "<Right>", "l", opts)
keymap("v", "<Left>", "h", opts)
keymap("v", "<Down>", "j", opts)
keymap("v", "<Up>", "k", opts)

-- exchange ; and :
--keymap("n", ";", ":", opts)
--keymap("n", ":", ";", opts)
