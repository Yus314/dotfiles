{ pkgs, unstable, ... }:
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
    #dropbox
    #zoom
    #swayn
    waybar
    wl-clipboard
    #swaylock
    #swayidle
    wlogout
    #slack
    #zoom
    kitty
    gdrive3
    drive
    dropbox
    rclone
    (unstable.zotero-beta)
    # adobe-reader
    foot
    pinta
    nvitop
  ];
}
