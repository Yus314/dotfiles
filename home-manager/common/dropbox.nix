{ pkgs, ... }:
{
  systemd.user.services.dropbox = {
    Unit = {
      Description = "Dropbox service";
      After = [ "network-online.target" ];
    };
    Service = {
      Type = "notify";
      ExecStartPre = "/run/current-system/sw/bin/mkdir -p %h/dropbox";
      ExecStart = "${pkgs.rclone}/bin/rclone --config=%h/.config/rclone/dropbox.conf --vfs-cache-mode writes --ignore-checksum mount \"dropbox:\" \"dropbox\" --allow-other";
      ExecStop = "/run/wrappers/bin/fusermount -u %h/dropbox/%i";
      Environment = [ "PATH=/run/wrappers/bin/:$PATH" ];
    };
    Install.WantedBy = [ "default.target" ];
  };
  home.file."/.config/rclone/dropbox.conf" = {
    source = ./dropbox.conf;
  };
}
