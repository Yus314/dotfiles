{ inputs, pkgs, ... }:
{
  ext.xdg.enable = true;
  programs = {
    direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };
    eza.enable = true;

    fd.enable = true;

    fzf.enable = true;

    ripgrep.enable = true;

    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
  };
  home.packages = with pkgs; [
    # --- CLI Utilities ---
    tldr # Simplified man pages
    pandoc # Universal document converter
    just # Command runner
    nix-output-monitor # Nix build output monitor
    unzip # ZIP archive utility
    cloudflared # Cloudflare Tunnel daemon
    carapace # Command argument completion generator
    rclone # Rsync for cloud storage
    nix-init
    ghq
    pinentry-curses
    plantuml
    cachix
    nvfetcher
    gemini-cli
    nix-search-cli
    jq
    yq

    # --- GUI Applications ---
    zotero # Reference management software

    anki-bin # Spaced repetition flashcard program (binary version)
    mpv # Feature-rich media player
    rquickshare
  ];
  xdg.enable = true;
}
