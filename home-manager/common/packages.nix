{
  pkgs,
  unstable,
  ...
}:
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
    #zoom
    #swayn
    #slack
    #zoom
    kitty
    gdrive3
    drive
    #dropbox
    rclone
    # adobe-reader
    #(xremap)
    qutebrowser

    #nyxt
    kakoune
    #(unstable.qutebrowser)
    zotero
  ];
}
