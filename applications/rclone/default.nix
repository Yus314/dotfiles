{ config, pkgs, ... }:
{
  home.packages = [ pkgs.rclone ];
  xdg.configFile."rclone/rclone.conf".text = ''
    [dropbox]
    type = dropbox
    # token will be loaded from environment variables or rclone config
  '';
}
