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
            				  eval "$(zoxide init zsh)"
      					  EDITOR=nvim
    '';
    sessionVariables = {
      EDITOR = "nvim";
    };
    plugins = [ ];
  };
}
