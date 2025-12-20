{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    signing = {
      key = "D2A9353AEDF9200A";
      format = "openpgp";
      signByDefault = true;
    };
    settings = {
      user = {
        name = "Yus314";
        email = "shizhaoyoujie@gmail.com";
      };
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
