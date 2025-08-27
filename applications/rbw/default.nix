{ pkgs, ... }:
{
  programs.rbw = {
    enable = true;
    settings = {
      email = "shizhaoyoujie@gmail.com";
      pinentry = if pkgs.stdenv.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-gnome3;
      lock_timeout = 3600; # 1 hour
    };
  };
}
