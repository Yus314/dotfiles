{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    terminal = "screen-256color";
    extraConfig = ''
      set -ga terminal-features ",alacritty:RGB"
      set -g set-clipboard on

      # kakoune-scrollback (requires tmux 3.3+)
      bind-key H run-shell -b '                                              \
          pane="#{pane_id}"                                                 ;\
          cx=$(tmux display-message -p -t "$pane" "#{cursor_x}")            ;\
          cy=$(tmux display-message -p -t "$pane" "#{cursor_y}")            ;\
          h=$(tmux display-message -p -t "$pane" "#{pane_height}")          ;\
          w=$(tmux display-message -p -t "$pane" "#{pane_width}")           ;\
          tmpf=$(mktemp)                                                    ;\
          tmux capture-pane -t "$pane" -e -p -S - > "$tmpf"                 ;\
          tmux new-window -n scrollback                                       \
              "SCROLLBACK_PIPE_DATA=\"0:$((cx+1)),$((cy+1)):''${h},''${w}\"   \
               ${pkgs.kakounePlugins.kakoune-scrollback}/bin/kakoune-scrollback --tmux-pane $pane < \"$tmpf\" ; \
               rm -f \"$tmpf\""                                               \
      '
    '';
  };
}
