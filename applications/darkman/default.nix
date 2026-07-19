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

  hermesSkinScript = skin: ''
    HERMES_CONFIG="$HOME/.hermes/config.yaml"

    if [ -L "$HERMES_CONFIG" ]; then
      HERMES_CONFIG=$(${pkgs.coreutils}/bin/readlink -f "$HERMES_CONFIG")
    fi

    if [ -f "$HERMES_CONFIG" ]; then
      tmp="$HERMES_CONFIG.tmp.$$"
      HERMES_SKIN="${skin}" ${pkgs.perl}/bin/perl -0pe '
        my $skin = $ENV{HERMES_SKIN};
        s{
          (^display:\n)
          (.*?)
          (?=^[^ \n]|\z)
        }{
          my ($head, $body) = ($1, $2);
          if ($body =~ s/^  skin:.*$/  skin: $skin/m) {
            $head . $body
          } else {
            $head . $body . "  skin: $skin\n"
          }
        }egmsx
      ' "$HERMES_CONFIG" > "$tmp" && ${pkgs.coreutils}/bin/mv "$tmp" "$HERMES_CONFIG"

      if ${pkgs.procps}/bin/pgrep -x hermes > /dev/null; then
        ${pkgs.libnotify}/bin/notify-send -a "darkman" "Hermes" \
          "CLI skin を ${skin} に変更しました。新しい Hermes 起動時に反映されます。" || true
      fi
    fi
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
        if [ -L "$CLAUDE_JSON" ]; then
          CLAUDE_JSON=$(${pkgs.coreutils}/bin/readlink -f "$CLAUDE_JSON")
        fi
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
      bat-theme = ''
        ${pkgs.coreutils}/bin/ln -sf \
          "${config.xdg.configHome}/bat/config.dark" \
          "${config.xdg.configHome}/bat/config"
      '';
      hermes-skin = hermesSkinScript "modus-vivendi";
    };
    lightModeScripts = {
      gtk-theme = ''
        ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
        ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita'"
      '';
      claude-code-theme = ''
        CLAUDE_JSON="$HOME/.claude.json"
        if [ -L "$CLAUDE_JSON" ]; then
          CLAUDE_JSON=$(${pkgs.coreutils}/bin/readlink -f "$CLAUDE_JSON")
        fi
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
      bat-theme = ''
        ${pkgs.coreutils}/bin/ln -sf \
          "${config.xdg.configHome}/bat/config.light" \
          "${config.xdg.configHome}/bat/config"
      '';
      hermes-skin = hermesSkinScript "modus-operandi";
    };
  };
  gtk.enable = true;
}
