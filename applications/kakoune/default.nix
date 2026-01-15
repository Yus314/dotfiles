{ pkgs, ... }:
{
  programs.kakoune = {
    enable = true;
    plugins = [ pkgs.kakoune-lsp ];
    colorSchemePackage = pkgs.kakounePlugins.kakoune-themes;
    config = {
      colorScheme = "modus-operandi";
      keyMappings = [
        {
          mode = "normal";
          key = "d";
          effect = "h";
        }
        {
          mode = "normal";
          key = "s";
          effect = "j";
        }
        {
          mode = "normal";
          key = "t";
          effect = "k";
        }
        {
          mode = "normal";
          key = "n";
          effect = "l";
        }
        {
          mode = "normal";
          key = "h";
          effect = "s";
        }
      ];
    };
  };
}
