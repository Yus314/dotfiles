{ pkgs, config, ... }:
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
    initContent = ''
                        	if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
                        		source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 
                        	fi
                  			if [ -f ${"ZDOTDIR:-~"}/.p10k.zsh ]; then
                               source ${"ZDOTDIR:-~"}/.p10k.zsh
                  			fi
            				  eval "$(zoxide init zsh)"
      					  EDITOR=nvim
    '';
    sessionVariables = {
      EDITOR = "nvim";
    };
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];
  };
  home.file."${config.xdg.configHome}/zsh/.p10k.zsh".text = builtins.readFile ./.p10k.zsh;
}
