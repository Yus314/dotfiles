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
    onedrive
    marp-cli
  ];
}
