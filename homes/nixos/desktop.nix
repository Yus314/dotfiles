{ pkgs, ... }:
{
  imports = [
    ../desktop.nix
    ../../applications/hyprland
    ../../applications/sway
    ../../applications/i3
    ../../applications/tofi
    ../../applications/foot
  ];
  home.packages = with pkgs; [
    xfce.thunar
    xfce.tumbler
    gscreenshot
    guacamole-server
    waybar
    wl-clipboard
    #swaylock
    #swayidle
    wlogout
    pinta
    nyxt
  ];
  #  systemd.user.services.shingata = {

  #    Install = {
  #      WantedBy = [ "default.target" ];
  #    };
  #    Service = {
  #
  #      ExecStart = ''
  #        	    ${pkgs.dbus}/bin/dbus-monitor "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/controller',arg0='org.fcitx.Fcitx.Controller1'"
  #        	  '';
  #    };
  #  };

  programs.waybar = {
    enable = false;
    systemd.enable = true;
  };
}
