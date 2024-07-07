{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    userName = "Yus314";
    userEmail = "shizhaoyoujie@gmail.com";
    extraConfig = {
      core = {
        editor = "nvim";
      };
      pull.rebase = false;
    };
  };
}
