{ pkgs, ... }:
{
  # Temporarily disabled - causes package conflict in CI
  # home.packages = [ pkgs.kakoune-lsp ];

  programs.kakoune = {
    enable = true;
    plugins = [pkgs.kakounePlugins.kakoune-scrollback ];
    # colorSchemePackage = pkgs.kakounePlugins.kakoune-themes;  # Package doesn't exist in nixpkgs
    config = {
      # colorScheme = "modus-operandi";  # Requires colorSchemePackage
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
        {
          mode = "normal";
          key = "l";
          effect = "d";
        }
        {
          mode = "normal";
          key = "<a-y>";
          effect = "<a-i>";
        }
        {
          mode = "normal";
          key = "<a-v>";
          effect = "<a-S>";
        }
        {
          mode = "normal";
          key = "D";
          effect = "H";
        }
        {
          mode = "normal";
          key = "S";
          effect = "J";
        }
        {
          mode = "normal";
          key = "T";
          effect = "K";
        }
        {
          mode = "normal";
          key = "N";
          effect = "L";
        }
        {
          mode = "normal";
          key = "L";
          effect = "N";
        }
        {
          mode = "normal";
          key = "H";
          effect = "S";
        }
      ];
    };
  };
}
