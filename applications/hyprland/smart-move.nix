{ pkgs }:

{
  hyprland-smart-move-left = pkgs.writeShellScriptBin "hyprland-smart-move-left" ''
    current_ws=$(${pkgs.hyprland}/bin/hyprctl activeworkspace | grep "workspace ID" | cut -d' ' -f3)
    
    if ${pkgs.hyprland}/bin/hyprctl activewindow | grep -q "Invalid"; then
      # No active window: move to previous workspace
      target_ws=$((current_ws > 1 ? current_ws - 1 : 1))
      ${pkgs.hyprland}/bin/hyprctl dispatch workspace $target_ws
    else
      # Active window exists: move window left
      ${pkgs.hyprland}/bin/hyprctl dispatch movewindow l
    fi
  '';

  hyprland-smart-move-right = pkgs.writeShellScriptBin "hyprland-smart-move-right" ''
    current_ws=$(${pkgs.hyprland}/bin/hyprctl activeworkspace | grep "workspace ID" | cut -d' ' -f3)
    
    if ${pkgs.hyprland}/bin/hyprctl activewindow | grep -q "Invalid"; then
      # No active window: move to next workspace
      target_ws=$((current_ws < 9 ? current_ws + 1 : 9))
      ${pkgs.hyprland}/bin/hyprctl dispatch workspace $target_ws
    else
      # Active window exists: move window right
      ${pkgs.hyprland}/bin/hyprctl dispatch movewindow r
    fi
  '';
}