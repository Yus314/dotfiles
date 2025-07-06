{ pkgs, config, ... }:
{
  programs.vim = {
    enable = true;
    extraConfig = ''
      if filereadable(expand('${config.xdg.configHome}/vim/vimrc'))
        source ${config.xdg.configHome}/vim/vimrc
      endif
    '';
  };
  xdg.configFile."vim/vimrc".source = ./vimrc; # vimrc is read by vscode of Windows too
}
