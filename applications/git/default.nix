{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    userName = "Yus314";
    userEmail = "shizhaoyoujie@gmail.com";
    signing = {
      key = "A9CD106F20CB7E85";
      format = "openpgp";
      signByDefault = true;
    };
    extraConfig = {
      core = {
        editor = "nvim";
      };
      pull.rebase = false;
    };
    ignores = [
      ".DS_Store"
      ".direnv"
    ];
  };
}
