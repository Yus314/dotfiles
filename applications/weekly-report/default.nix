{
  pkgs,
  lib,
  ...
}:
{
  home.packages = [ pkgs.weekly-report ];

  systemd.user.services.generate-weekly-report = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "Generate weekly report in Markdown";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.weekly-report}/bin/generate-weekly-report";
    };
  };

  systemd.user.timers.generate-weekly-report = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "Weekly report generation timer";
    Timer = {
      OnCalendar = "Sat 09:00";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
