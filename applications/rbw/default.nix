{ pkgs, ... }:
{
  programs.rbw = {
    enable = true;
    settings = {
      email = "shizhaoyoujie@gmail.com";
      pinentry = pkgs.pinentry-gnome3;
      lock_timeout = 3600; # 1 hour
    };
  };
}
