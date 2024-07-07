{ pkgs, config, ... }:
{
  users.users.Cloudflared = {
    group = "wheel";
    isSystemUser = true;
  };
  services.cloudflared = {
    enable = true;
    user = "kaki";
    tunnels = {
      "9495eeb0-3ed8-4420-a050-486d5ae442a8" = {
        credentialsFile = "${config.users.users.kaki.home}/.cloudflared/9495eeb0-3ed8-4420-a050-486d5ae442a8.json";
        default = "http_status:404";
      };
    };
  };
  systemd.services.lab2home_sub = {
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "systemd-resolved.service"
    ];
    serviceConfig = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token=eyJhIjoiZTU4ODdmZDg4NDFmZjRmZDQzZTQ2Y2QxZTAxYjM4MDkiLCJ0IjoiMGMzYzdiNmQtZDY1Yy00MTM0LWJiY2QtMzkzMDM4M2M4OGQ3IiwicyI6IllXTTNaalppTmpFdFpEZzJZUzAwTm1JMExUazJZekV0T0dKbE5HTTBOemRoTVRoaiJ9";
      ReStart = "always";
      User = "kaki";
      Group = "wheel";
    };
  };
}
