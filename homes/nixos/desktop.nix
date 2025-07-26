{ pkgs, inputs, ... }:
{
  imports = [
    ../desktop.nix
    ../../applications/hyprland
    ../../applications/sway
    ../../applications/i3
    ../../applications/tofi
    ../../applications/foot
    ../../applications/waybar
    ../../applications/rclone
  ];
  home.packages = with pkgs; [
    xfce.thunar
    xfce.tumbler
    gscreenshot
    wl-clipboard
    #swaylock
    #swayidle
    wlogout
    pinta
    nyxt
    # Temporarily disabled due to CI issues
    # inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
