{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    userName = "Yus314";
    userEmail = "shizhaoyoujie@gmail.com";
    signing = {
      key = "B0F6B192E4253A5DBD33A7F2D2A9353AEDF9200A";
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
