{ pkgs, ... }:
{
  # Temporarily disabled - causes package conflict in CI
  # home.packages = [ pkgs.kakoune-lsp ];

  programs.kakoune = {
    enable = true;
    plugins = [ ];
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
      ];
    };
  };
}
