{ inputs, pkgs, ... }:
{
  imports = [ inputs.zen-browser.homeModules.beta ];
  programs.zen-browser = {
    enable = true;
    profiles.kaki = {
      extensions = {
        packages = (
          with pkgs.firefox-addons;
          [
            bitwarden
            ublock-origin
            vimium
          ]
        );
        force = true;
        settings = {
          "{d7742d87-e61d-4b78-b8a1-b469842139fa}".settings = {
            keyMappings = ''
              # Insert your preferred key mappings here.
              unmap s
              unmap t
              unmap d
              unmap n
              unmap K
              unmap D
              unmap N
              map s scrollDown
              map t scrollUp
              map d goBack
              map n goForward
            '';
            settingsVersion = "2.3.1";
          };
        };
      };
      settings = {
        "browser.translations.neverTranslateLanguages" = "ja";
      };
      spaces = {
        "論文執筆" = {
          id = "{b2ee0332-848a-48c9-ac91-219f750c1fe9}";
          icon = "✒️";
          container = 2;
          position = 1000;
          theme = {
            type = "gradient";
            opacity = 0.848;
            colors = [
              {
                red = 96;
                green = 112;
                blue = 159;
                algorithm = "floating";
                primary = true;
                lightness = 50;
                position.x = 77;
                position.y = 77;
                type = "explicit-lightness";
              }
            ];
          };
        };
        "dotfiles" = {
          id = "{fde0087b-2fc9-4eca-a6e4-8bd65b086ae7}";
          icon = "💻️";
          container = 2;
          position = 2000;
          theme = {
            type = "gradient";
            opacity = 0.617;
            colors = [
              {
                red = 239;
                green = 138;
                blue = 118;
                algorithm = "floating";
                primary = true;
                lightness = 70;
                position.x = 220;
                position.y = 187;
                type = "explicit-lightness";
              }
            ];
          };
        };
        "雑多" = {
          id = "{f23f28f0-7e63-498e-affb-8f792c65211b}";
          position = 3000;
          theme = {
            type = "gradient";
            opacity = 0.405;
            colors = [
              {
                red = 253;
                green = 160;
                blue = 243;
                algorithm = "floating";
                primary = true;
                lightness = 81;
                position.x = 273;
                position.y = 54;
                type = "undefined";
              }
            ];
          };
        };
        "MoLe" = {
          id = "{b957980b-e548-4b52-baf6-dfe6ed68d123}";
          position = 4000;
          theme = {
            type = "gradient";
            opacity = 0.864;
            colors = [
              {
                red = 143;
                green = 58;
                blue = 197;
                algorithm = "floating";
                primary = true;
                lightness = 50;
                position.x = 190;
                position.y = 93;
                type = "explicit-lightness";
              }
            ];
          };
        };
        "ポケモンスリープ" = {
          id = "{cba3d74e-0e70-475a-8227-334fafb6fa22}";
          icon = "💤";
          position = 5000;
          theme = {
            type = "gradient";
            opacity = 0.821;
            colors = [
              {
                red = 225;
                green = 252;
                blue = 140;
                algorithm = "floating";
                primary = true;
                lightness = 77;
                position.x = 220;
                position.y = 323;
                type = "undefined";
              }
            ];
          };
        };
        "学校生活" = {
          id = "{2a3b4a3e-08e9-4863-87c7-03d3daf413cd}";
          position = 6000;
          theme = {
            type = "gradient";
            opacity = 0.5;
            colors = [
              {
                red = 255;
                green = 252;
                blue = 215;
                algorithm = "floating";
                primary = true;
                lightness = 92;
                position.x = 277;
                position.y = 328;
                type = "undefined";
              }
            ];
          };
        };
      };
      search = {
        force = true;
        default = "Kagi";
        engines = {
          "Kagi" = {
            urls = [ { template = "https://kagi.com/search?q={searchTerms}"; } ];
            icon = "https://kagi.com/favicon.ico";
            definedAliases = [ "@k" ];
          };
        };
      };
    };
  };
}
