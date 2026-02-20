{ config, pkgs, ... }:
let
  zathuraSourceConfig = ''
    for pid in $(${pkgs.procps}/bin/pgrep zathura); do
      ${pkgs.dbus}/bin/dbus-send --print-reply \
        --dest="org.pwmt.zathura.PID-$pid" \
        /org/pwmt/zathura \
        org.pwmt.zathura.SourceConfig \
        2>/dev/null || true
    done
  '';
in
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
      zathura-theme = ''
        ${pkgs.coreutils}/bin/ln -sf \
          "${config.xdg.configHome}/zathura/zathurarc.dark" \
          "${config.xdg.configHome}/zathura/zathurarc"
        ${zathuraSourceConfig}
      '';
    };
    lightModeScripts = {
      gtk-theme = ''
        ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
        ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita'"
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
      zathura-theme = ''
        ${pkgs.coreutils}/bin/ln -sf \
          "${config.xdg.configHome}/zathura/zathurarc.light" \
          "${config.xdg.configHome}/zathura/zathurarc"
        ${zathuraSourceConfig}
      '';
    };
  };
  gtk.enable = true;
}
