{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    userName = "Yus314";
    userEmail = "shizhaoyoujie@gmail.com";
    signing = {
      key = "D2A9353AEDF9200A";
      format = "openpgp";
      signByDefault = true;
    };
    extraConfig = {
      core = {
        editor = "emacs";
      };
      ghq.user = "Yus314";
      pull.rebase = false;
      github.user = "Yus314";
    };
    ignores = [
      ".DS_Store"
      ".direnv"
    ];
  };
}
