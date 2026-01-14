{ config, pkgs, ... }:
{
  services.darkman = {
    enable = true;
    settings = {
      lat = 35.68;
      lng = 139.65;
    };
    darkModeScripts = {
      gtk-theme = ''
        ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
        ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita-dark'"
      '';
      kitty-theme = ''
        for socket in /tmp/kitty-*; do
          [ -S "$socket" ] && ${pkgs.kitty}/bin/kitty @ --to "unix:$socket" set-colors --all --configured \
            ${pkgs.kitty-themes}/share/kitty-themes/themes/Modus_Vivendi.conf
        done
      '';
    };
    lightModeScripts = {
      gtk-theme = ''
        ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
        ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita'"
      '';
      kitty-theme = ''
        for socket in /tmp/kitty-*; do
          [ -S "$socket" ] && ${pkgs.kitty}/bin/kitty @ --to "unix:$socket" set-colors --all --configured \
            ${pkgs.kitty-themes}/share/kitty-themes/themes/Modus_Operandi.conf
        done
      '';
    };
  };
  gtk.enable = true;
}
