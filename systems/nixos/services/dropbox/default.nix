{ pkgs, config, ... }:
{
  programs.fuse.userAllowOther = true;
  sops = {
    secrets = {
      "dropbox/token/access_token" = { };
      "dropbox/token/token_type" = { };
      "dropbox/token/refresh_token" = { };
      "dropbox/token/expiry" = { };
    };
    templates = {

      "dropbox.conf" = {
        owner = "kaki";
        group = "users";
        mode = "0440";
        content = ''
          [dropbox]
          type = dropbox
          token = {"access_token":"${config.sops.placeholder."dropbox/token/access_token"}","token_type":"${
            config.sops.placeholder."dropbox/token/token_type"
          }","refresh_token":"${config.sops.placeholder."dropbox/token/refresh_token"}","expiry":"${
            config.sops.placeholder."dropbox/token/expiry"
          }"}
        '';
      };
    };
  };
  systemd.user.services.dropbox = {
    description = "Dropbox service";
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "notify";
      ExecStartPre = "/run/current-system/sw/bin/mkdir -p %h/dropbox";
      ExecStart = "${pkgs.rclone}/bin/rclone --config=${
        config.sops.templates."dropbox.conf".path
      } --vfs-cache-mode writes --ignore-checksum mount \"dropbox:\" \"dropbox\" --allow-other";
      ExecStop = "/run/wrappers/bin/fusermount -u %h/dropbox/%i";
      Environment = [ "PATH=/run/wrappers/bin/:$PATH" ];
    };
    wantedBy = [ "default.target" ];

  };
}
