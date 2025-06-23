local wezterm = require("wezterm")

local config = {}

if wezterm.config_builder then
	config = wezterm.config_builder()
end

-- カラースキームの設定
config.color_scheme = "OneDark (base16)"

-- フォントの設定
config.font = wezterm.font("Bizin Gothic Discord NF")
config.font_size = 14.4
config.use_ime = false

config.enable_wayland = false
config.front_end = "OpenGL"
config.use_ime = false

-- スクロールの設定
local act = wezterm.action

config.keys = {
	{ key = "K", mods = "SHIFT|CTRL", action = act.ClearScrollback("ScrollbackOnly") },
	{ key = "T", mods = "SHIFT|CTRL", action = act.ScrollByPage(-1) },
	{ key = "H", mods = "SHIFT|CTRL", action = act.ScrollByPage(1) },
	{ key = "[", mods = "CTRL", action = act.ActivateTabRelative(-1) },
	{ key = "]", mods = "CTRL", action = act.ActivateTabRelative(1) },
	{ key = "w", mods = "ALT", action = act.CloseCurrentTab({ confirm = true }) },
	{ key = "a", mods = "ALT", action = act.SpawnTab("CurrentPaneDomain") },
}
config.disable_default_key_bindings = true

return config
