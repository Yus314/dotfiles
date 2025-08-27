{ pkgs, config, ... }:
{
  programs.less = {
    enable = true;
    config = ''
      #command

      #line-edit

      #env
      LESSHISTFILE = ${config.xdg.dataHome}/less/history
    '';
  };
}
