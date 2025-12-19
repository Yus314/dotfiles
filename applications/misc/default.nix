{ inputs, pkgs, ... }:
{
  ext.xdg.enable = true;
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
    go-task # Task runner
    nix-output-monitor # Nix build output monitor
    unzip # ZIP archive utility
    cloudflared # Cloudflare Tunnel daemon
    marp-cli # Markdown presentation ecosystem CLI
    #vimgolf # Vim code golf client
    carapace # Command argument completion generator
    gdrive3 # Google Drive CLI Client (consider using rclone instead?)
    # drive # Another Google Drive CLI Client (choose one or use rclone)
    rclone # Rsync for cloud storage
    # xremap # Key remapper (commented out)
    nix-init
    ghq
    pinentry-curses
    plantuml
    aider-chat # AI pair programming tool in your terminal
    cachix
    nvfetcher
    claude-code
    gemini-cli
    nix-search-cli
    jq
    yq
    # github-copilot-cli # Temporarily disabled due to man-cache build issues

    # --- GUI Applications ---
    zathura # Document viewer with vi-like keybindings
    kakoune # Modal editor with multiple selections
    zotero # Reference management software

    anki-bin # Spaced repetition flashcard program (binary version)
    mpv # Feature-rich media player
  ];
  xdg.enable = true;
}
