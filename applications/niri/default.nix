{ pkgs, inputs, ... }:
let
  defaultKeyBind = import ./defaultKeyBind.nix;
  luncher = "tofi-drun --drun-launch=true";
in
{
  imports = [
    inputs.niri.homeModules.niri
  ];

  programs.niri = {
    enable = true;
    package = inputs.niri.packages.${pkgs.system}.niri-unstable;

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
      };

      environment = {
        "NIXOS_OZONE_WL" = "1";
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
          command = [ "waybar" ];
        }
      ];
    };
  };
}
