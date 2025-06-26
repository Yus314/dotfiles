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
        editor = "nvim";
      };
      ghq.user = "Yus314";
      pull.rebase = false;
    };
    ignores = [
      ".DS_Store"
      ".direnv"
    ];
  };
}
