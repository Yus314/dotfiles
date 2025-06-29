{ pkgs, config, ... }:
{
  programs.fuse.userAllowOther = true;
  sops = {
    secrets = {
      dropbox-token-env = {
        sopsFile = ./secrets.yaml;
        owner = "kaki";
        group = "users";
        mode = "0640";
      };
    };
  };
  systemd.user.services.dropbox = {
    description = "Dropbox service";
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "notify";
      ExecStartPre = "${pkgs.coreutils-full}/bin/mkdir -p %h/dropbox";
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone \
        --vfs-cache-mode writes \
        --ignore-checksum mount "dropbox:" "%h/dropbox" \
        --allow-other
      '';
      ExecStop = "${pkgs.fuse}/bin/fusermount -u %h/dropbox";
      Environment = [ "PATH=/run/wrappers/bin/:$PATH" ];
      EnvironmentFile = "${config.sops.secrets.dropbox-token-env.path}";
    };
    wantedBy = [ "default.target" ];
  };
}
