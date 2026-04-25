{ ... }:
{
  xdg.configFile."kasane/config.toml".text = ''
    [window]
    maximized = true
    [font]
    family = "Bizin Gothic NF"
    size = 24.0
    fallback_list = ["Noto Sans CJK JP", "Noto Color Emoji"]
    [search]
    dropdown = true
    [plugins]
    enabled = ["cursor_line", "color_preview", "sel_badge", "fuzzy_finder", "image_preview"]
  '';
}
