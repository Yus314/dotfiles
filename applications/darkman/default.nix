{ config, pkgs, ... }:
{
  services.darkman = {
    enable = true;
    darkModeScripts = {
      gtk-theme = ''
                ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
        	${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita-dark'"
      '';
    };
  };
  gtk.enable = true;
}
