{
  pkgs,
  inputs,
  lib,
  config,
  ...
}:
let
  defaultKeyBind = import ./defaultKeyBind.nix;
  wallPaperPath = "${config.xdg.dataHome}/SpotlightArchive/";

  # ランダム壁紙選択スクリプト
  randomWallpaper = pkgs.writeShellScriptBin "random-wallpaper" ''
    WALLPAPER_DIR="${wallPaperPath}"

    # ディレクトリが存在し、画像ファイルがあるか確認
    if [ -d "$WALLPAPER_DIR" ]; then
      # 画像ファイルをランダムに選択
      WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" \) | shuf -n 1)

      if [ -n "$WALLPAPER" ]; then
        # swwwデーモンの起動を待つ
        ${lib.getExe pkgs.swww} img "$WALLPAPER" --transition-type fade --transition-duration 2
      fi
    fi
  '';
in
{
  imports = [
    inputs.niri.homeModules.niri
  ];

  programs.niri = {
    enable = true;
    package = pkgs.niri;

    settings = {
      # デュアルモニター設定
      outputs = {
        "DVI-D-1" = {
          mode = {
            width = 1920;
            height = 1080;
            refresh = 60.0;
          };
          position = {
            x = 0;
            y = 0;
          };
        };
        "HDMI-A-1" = {
          mode = {
            width = 1920;
            height = 1080;
            refresh = 74.97;
          };
          position = {
            x = 1920;
            y = 0;
          };
        };
      };

      binds = defaultKeyBind // {
        "Mod+Shift+Ctrl+Return".action.spawn = [
          "tofi-drun"
          "--drun-launch=true"
        ];
      };

      input = {
        mod-key = "Alt";
        mod-key-nested = "Alt";
        tablet = {
          map-to-output = "HDMI-A-1";
        };
      };

      environment = {
        "NIXOS_OZONE_WL" = "1";
        "DISPLAY" = ":0";
      };

      animations = {
        enable = true;
        horizontal-view-movement = {
          enable = true;
          kind = {
            "spring" = {
              damping-ratio = 0.8;
              epsilon = 0.0001;
              stiffness = 800;
            };
          };
        };
      };

      layer-rules = [
        {
          matches = [ { namespace = "^wallpaper$"; } ];
          place-within-backdrop = true;
        }
      ];

      layout = {
        background-color = "transparent";
      };

      # 自動起動プログラム
      spawn-at-startup = [
        {
          command = [
            "fcitx5"
            "-d"
          ];
        }
        {
          command = [ "${lib.getExe pkgs.xwayland-satellite}" ];
        }
        {
          # ランダム壁紙を設定
          command = [ "${lib.getExe randomWallpaper}" ];
        }
      ];
      prefer-no-csd = true;
    };
  };
}
