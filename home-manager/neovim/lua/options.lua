local options = {
	number = true,
	tabstop = 4,
	shiftwidth = 4,
	smartindent = true,
	termguicolors = true,
}

for k, v in pairs(options) do
	vim.opt[k] = v
end
