{ inputs, pkgs, ... }:
{
  programs = {
    bat.enable = true;
    direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };
    eza.enable = true;

    fd.enable = true;

    fzf.enable = true;

    gh.enable = true;

    ripgrep.enable = true;

    starship = {
      enable = true;
      enableZshIntegration = false;
      enableBashIntegration = false;
      enableFishIntegration = false;
      enableNushellIntegration = true;
    };
    tmux = {
      enable = true;
      terminal = "screen-256color";
      extraConfig = ''
        set -ga terminal-features ",alacritty:RGB"
      '';
    };

    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      enableNushellIntegration = true;
    };
  };
  home.packages = with pkgs; [
    # --- CLI Utilities ---
    tldr # Simplified man pages
    pandoc # Universal document converter
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
    nix-init
    ghq

    # --- GUI Applications ---
    zathura # Document viewer with vi-like keybindings
    # nyxt # Another keyboard-focused browser (commented out)
    kakoune # Modal editor with multiple selections
    zotero # Reference management software

    anki-bin # Spaced repetition flashcard program (binary version)
    mpv # Feature-rich media player
    aider-chat # AI pair programming tool in your terminal
    cachix
    nvfetcher
  ];
}
