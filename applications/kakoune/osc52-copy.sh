#!/usr/bin/env bash
set -euo pipefail

input="$(cat)"

try_wl_copy() {
  command -v wl-copy >/dev/null 2>&1 || return 1
  [ -n "${WAYLAND_DISPLAY-}" ] || return 1
  printf %s "$input" | wl-copy -n >/dev/null 2>&1
}

try_pbcopy() {
  command -v pbcopy >/dev/null 2>&1 || return 1
  printf %s "$input" | pbcopy >/dev/null 2>&1
}

send_osc52() {
  local b64
  b64="$(printf %s "$input" | base64 | tr -d '\n')"
  if [ -n "${TMUX-}" ]; then
    printf '\033Ptmux;\033\033]52;c;%s\007\033\\' "$b64"
  else
    printf '\033]52;c;%s\007' "$b64"
  fi
}

try_wl_copy || try_pbcopy || send_osc52
