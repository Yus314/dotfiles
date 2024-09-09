{ pkgs, ... }:
{
  home.packages = with pkgs; [
    #cowsay
    tldr
    pandoc
    texliveTeTeX
    iconv
    just
    zathura
    unzip
    cloudflared
    marp-cli
    vimgolf
    carapace
    zoom
    sway
    waybar
    wl-clipboard
    swaylock
    swayidle
    wlogout
  ];
}
