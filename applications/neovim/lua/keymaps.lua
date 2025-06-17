local opts = { noremap = true, silent = true }
local keymap = vim.api.nvim_set_keymap
-- keymap("", "<C-h>", "<80>kb", opts)
--vim.g.mapleader = "\<BS>"
-- vim.api.nvim_set_var("mapleader", "<80>kb")
keymap("n", " ", "<NOP>", opts)
vim.api.nvim_set_var("mapleader", " ")
vim.api.nvim_set_var("maplocalleader", " ")

keymap("n", "<leader>f", "<cmd>Telescope file_browser<CR>", opts)

keymap("n", "[b", "<cmd>BufferPrevious<CR>", opts)
keymap("n", "]b", "<cmd>BufferNext<CR>", opts)
keymap("n", "<C-w>w", "<cmd>BufferClose<CR>", opts)

-- コマンドラインモードのマッピング
vim.api.nvim_set_keymap("i", "<C-j>", "<Plug>(skkeleton-enable)", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-j>", "<Plug>(skkeleton-enable)", { noremap = true, silent = true })
vim.api.nvim_set_keymap("c", "<C-j>", "<Plug>(skkeleton-enable)", { noremap = true, silent = true })
vim.api.nvim_set_keymap("i", "<C-l>", "<Plug>(skkeleton-disable)", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<C-l>", "<Plug>(skkeleton-disable)", { noremap = true, silent = true })
vim.api.nvim_set_keymap("c", "<C-l>", "<Plug>(skkeleton-disable)", { noremap = true, silent = true })

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

-- for move window
keymap("n", "<C-w><Right>", "<C-w>l", opts)
keymap("n", "<C-w><Left>", "<C-w>h", opts)
keymap("n", "<C-w><Down>", "<C-w>j", opts)
keymap("n", "<C-w><Up>", "<C-w>k", opts)

-- exchange ; and :
--keymap("n", ";", ":", opts)
--keymap("n", ":", ";", opts)
