{ pkgs, ... }: {
  programs.zsh = {
    enable = true;
    autocd = true;
    history = { ignoreAllDups = true; };
    enableCompletion = true;
    syntaxHighlighting = { enable = true; };
    enableAutosuggestions = true;
    initExtra = ''
      source ~/.p10k.zsh
      eval zoxide init zsh
    '';
    plugins = [{
      name = "powerlevel10k";
      src = pkgs.zsh-powerlevel10k;
      file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
    }];
  };
  home.file.".p10k.zsh".text = builtins.readFile ./.p10k.zsh;
}
