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
<<<<<<< HEAD
    zotero-beta
    # adobe-reader
    foot
    pinta
    nvitop
=======
    # adobe-reader
    #(xremap)
>>>>>>> 6971f88731a88dbeae23c3a7526a3203563003fc
    qutebrowser

    #nyxt
    kakoune
    #(unstable.qutebrowser)
    zotero
  ];
}
