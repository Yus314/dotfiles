{pkgs, ...}: {
  programs.zsh = {
    enable = true;
    autocd = true;
    history = {
      ignoreAllDups = true;
    };
    enableCompletion = true;
    syntaxHighlighting = {
      enable = true;
    };
    #autosuggestion = {
    #	enable = true;
    #};
    enableAutosuggestions = true;
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];
  };
}
