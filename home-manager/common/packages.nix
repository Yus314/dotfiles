{ pkgs, ... }:
{
  home.packages = with pkgs; [
    #cowsay
    tldr
    pandoc
    texliveTeTeX
    iconv
    just
    marp-cli
    zathura
    cloudflared
  ];
}
