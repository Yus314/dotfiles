{
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    # --- CLI Utilities ---
    tldr # Simplified man pages
    pandoc # Universal document converter
    # texliveTeTeX # Basic TeX distribution. Consider texlive.combined.scheme-medium or full for more features.
    texlive.combined.scheme-small # A slightly larger but still minimal TeX setup
    just # Command runner
    unzip # ZIP archive utility
    cloudflared # Cloudflare Tunnel daemon
    marp-cli # Markdown presentation ecosystem CLI
    vimgolf # Vim code golf client
    carapace # Command argument completion generator
    gdrive3 # Google Drive CLI Client (consider using rclone instead?)
    # drive # Another Google Drive CLI Client (choose one or use rclone)
    rclone # Rsync for cloud storage
    # xremap # Key remapper (commented out)

    # --- GUI Applications ---
    zathura # Document viewer with vi-like keybindings
    kitty # Fast, feature-rich GPU-based terminal emulator
    qutebrowser # Keyboard-focused browser with a minimal GUI
    # nyxt # Another keyboard-focused browser (commented out)
    kakoune # Modal editor with multiple selections
    zotero # Reference management software

    anki-bin # Spaced repetition flashcard program (binary version)
    mpv # Feature-rich media player
    aider-chat # AI pair programming tool in your terminal
    cachix
    code-cursor
    nvfetcher
  ];
}
