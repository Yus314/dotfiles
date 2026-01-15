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
      claude-code-theme = ''
        CLAUDE_JSON="$HOME/.claude.json"
        if [ -f "$CLAUDE_JSON" ]; then
          ${pkgs.jq}/bin/jq '.theme = "dark"' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && \
            mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
          if ${pkgs.procps}/bin/pgrep -x claude > /dev/null; then
            ${pkgs.libnotify}/bin/notify-send -a "darkman" "Claude Code" \
              "テーマを dark に変更しました。再起動で適用されます。"
          fi
        fi
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
      claude-code-theme = ''
        CLAUDE_JSON="$HOME/.claude.json"
        if [ -f "$CLAUDE_JSON" ]; then
          ${pkgs.jq}/bin/jq '.theme = "light"' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && \
            mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
          if ${pkgs.procps}/bin/pgrep -x claude > /dev/null; then
            ${pkgs.libnotify}/bin/notify-send -a "darkman" "Claude Code" \
              "テーマを light に変更しました。再起動で適用されます。"
          fi
        fi
      '';
    };
  };
  gtk.enable = true;
}
