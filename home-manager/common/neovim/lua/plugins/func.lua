-- func.lua
local M = {}

M.browserfunc = function(url)
	local handle = io.popen('google-chrome --app=' .. url)
	handle:close()
end

return M
