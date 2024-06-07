{ pkgs, ... }:
{
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
    autosuggestion = {
      enable = true;
    };
    initExtra = ''
                  	if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
                  		source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 
                  	fi
            			if [ -f ~/.p10k.zsh ]; then
                        source ~/.p10k.zsh
            			fi
      				  eval "$(zoxide init zsh)"
    '';
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];
  };
  home.file.".p10k.zsh".text = builtins.readFile ./.p10k.zsh;
}
