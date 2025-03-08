{ pkgs, ... }:
{
  home.packages = with pkgs; [
    xfce.thunar
    xfce.tumbler
    gscreenshot
    guacamole-server
    waybar
    wl-clipboard
    #swaylock
    #swayidle
    wlogout
    pinta
    nyxt
  ];
}
