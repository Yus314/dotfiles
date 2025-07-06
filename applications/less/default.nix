{ pkgs, config, ... }:
{
  programs.less = {
    enable = true;
    keys = ''
      #command

      #line-edit

      #env
      LESSHISTFILE = ${config.xdg.dataHome}/less/history
    '';
  };
}
