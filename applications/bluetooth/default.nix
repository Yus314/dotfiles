{ pkgs, ... }:
let
  deviceAddress = "20:74:CF:AF:BF:6E";
  deviceName = "OpenRun Pro";

  openrunToggle = pkgs.writeShellApplication {
    name = "openrun-toggle";
    runtimeInputs = with pkgs; [
      bluez
      coreutils
      libnotify
    ];
    text = ''
      device=${deviceAddress}
      device_name=${pkgs.lib.escapeShellArg deviceName}
      requested_action="''${1:-toggle}"

      notify_failure() {
        notify-send \
          --app-name=Bluetooth \
          --urgency=critical \
          "Bluetooth connection failed" \
          "$1"
      }

      if ! device_info="$(bluetoothctl info "$device" 2>/dev/null)"; then
        notify_failure "$device_name is not paired"
        exit 1
      fi

      if [[ "$device_info" == *"Connected: yes"* ]]; then
        connected=true
      else
        connected=false
      fi

      case "$requested_action" in
        status)
          if $connected; then
            printf 'connected\n'
          else
            printf 'disconnected\n'
          fi
          exit 0
          ;;
        toggle)
          if $connected; then
            action=disconnect
          else
            action=connect
          fi
          ;;
        connect | disconnect)
          action="$requested_action"
          ;;
        *)
          printf 'Usage: openrun-toggle [toggle|connect|disconnect|status]\n' >&2
          exit 2
          ;;
      esac

      if { [[ "$action" == connect ]] && $connected; } || {
        [[ "$action" == disconnect ]] && ! $connected;
      }; then
        notify-send --app-name=Bluetooth "$device_name" "Already ''${action}ed"
        exit 0
      fi

      if ! output="$(timeout 20s bluetoothctl "$action" "$device" 2>&1)"; then
        notify_failure "''${output:0:200}"
        exit 1
      fi

      if ! device_info="$(bluetoothctl info "$device" 2>/dev/null)"; then
        notify_failure "Could not verify $device_name"
        exit 1
      fi

      if [[ "$action" == connect && "$device_info" == *"Connected: yes"* ]]; then
        notify-send --app-name=Bluetooth "$device_name" "Connected"
      elif [[ "$action" == disconnect && "$device_info" != *"Connected: yes"* ]]; then
        notify-send --app-name=Bluetooth "$device_name" "Disconnected"
      else
        notify_failure "The $action command completed, but the state did not change"
        exit 1
      fi
    '';
  };
in
{
  home.packages = [ openrunToggle ];
}
