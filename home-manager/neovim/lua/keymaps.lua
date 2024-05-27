local opts = { noremap = true, silent = true }
local keymap = vim.api.nvim_set_keymap
keymap("", "<Space>", "<Nop>", opts)
vim.g.mapleader = " "


keymap("n", "<leader>f", "<cmd>Telescope file_browser<CR>", opts)

keymap("n", "[b", "<cmd>BufferPrevious<CR>", opts)
keymap("n", "]b", "<cmd>BufferNext<CR>", opts)
keymap("n", "<C-w>w", "<cmd>BufferClose<CR>", opts)


