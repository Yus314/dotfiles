{ pkgs, ... }:
let
  fam = if pkgs.stdenv.isDarwin then "MesloLGS NF" else "Monospace";
in
{
  programs.alacritty = {
    enable = true;
    settings = {
      window = {
        dimensions = {
          lines = 30;
          columns = 100;
        };
        option_as_alt = "None";
      };
      font = {
        normal = {
          family = fam;
          style = "Regular";
        };
        bold = {
          family = fam;
          style = "Bold";
        };
        italic = {
          family = fam;
          style = "Italic";
        };
        size = 12.0;
      };
      colors = {
        primary = {
          background = "#24283b";
          foreground = "#a9b1d6";
        };

        normal = {
          black = "#32344a";
          red = "#f7768e";
          green = "#9ece6a";
          yellow = "#e0af68";
          blue = "#7aa2f7";
          magenta = "#ad8ee6";
          cyan = "#449dab";
          white = "#9699a8";
        };

        bright = {
          black = "#444b6a";
          red = "#ff7a93";
          green = "#b9f27c";
          yellow = "#ff9e64";
          blue = "#7da6ff";
          magenta = "#bb9af7";
          cyan = "#0db9d7";
          white = "#acb0d0";
        };
      };
    };
  };
}
