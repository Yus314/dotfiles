local wezterm = require 'wezterm'

local config = {}

if wezterm.config_builder then
	config = wezterm.config_builder()
end

-- カラースキームの設定
config.color_scheme = 'OneDark (base16)'
config.window_decorations = "RESIZE"

-- スクロールの設定
local act = wezterm.action

config.keys = {
	{ key = "UpArrow",   mods = "SHIFT", action = act.ScrollByPage(-1) },
	{ key = "DownArrow", mods = "SHIFT", action = act.ScrollByPage(1) },
}

return config
