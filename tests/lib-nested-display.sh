#!/usr/bin/env bash
# Starts a throwaway nested compositor and reports its Wayland display.
#
# Every harness that instantiates the real Panel must use this. The panel is a
# layer-shell surface that primes exclusive keyboard focus: run it on the
# developer's own session and it steals the keyboard for the length of the run,
# and their typing lands in the panel's search field instead of their apps.
#
# Usage:
#   . "$(dirname "$0")/lib-nested-display.sh"
#   start_nested_display "$sandbox"      # sets NESTED_DISPLAY and NESTED_PID
#   stop_nested_display                  # safe to call from a trap
#
# Requires Hyprland; callers should skip cleanly when it is missing.

NESTED_DISPLAY=""
NESTED_PID=""

# Wait for the compositor to actually go. It takes a second or two to unwind,
# and a run that returns while its compositor is still up leaves a stray
# fullscreen surface on the machine.
stop_nested_display() {
  [[ -z $NESTED_PID ]] && return 0
  kill -TERM "$NESTED_PID" 2>/dev/null
  for _ in $(seq 1 30); do
    kill -0 "$NESTED_PID" 2>/dev/null || break
    sleep 0.2
  done
  kill -0 "$NESTED_PID" 2>/dev/null && kill -KILL "$NESTED_PID" 2>/dev/null
  wait "$NESTED_PID" 2>/dev/null
  NESTED_PID=""
  return 0
}

start_nested_display() {
  local sandbox=$1

  # Presentational acceptance runs at more than one viewport: a layout fault
  # that only appears when the panel has less room to work with is invisible on
  # a large display. NESTED_MONITOR overrides the default for a second pass.
  local monitor=${NESTED_MONITOR:-1200x900}
  cat >"$sandbox/hypr.conf" <<HYPR
monitor=,${monitor}@60,0x0,1
HYPR
  cat >>"$sandbox/hypr.conf" <<'HYPR'
misc {
  disable_hyprland_logo = true
  disable_splash_rendering = true
  force_default_wallpaper = 0
}
animations { enabled = false }
decoration { blur { enabled = false } }
HYPR

  Hyprland -c "$sandbox/hypr.conf" >"$sandbox/hypr.log" 2>&1 &
  NESTED_PID=$!

  # Identify the display by the lock file the compositor itself holds open.
  # Two tempting alternatives are wrong: diffing the socket directory breaks
  # when an earlier run left a stale socket behind, and asking the compositor
  # through exec-once reports the *host* display, because Hyprland does not
  # rewrite WAYLAND_DISPLAY in the environment its children inherit. Getting
  # this wrong points the harness at the real session.
  local lock target fd
  for _ in $(seq 1 80); do
    sleep 0.5
    lock=""
    for fd in /proc/"$NESTED_PID"/fd/*; do
      target=$(readlink "$fd" 2>/dev/null) || continue
      case $target in
        /run/user/"$(id -u)"/wayland-*.lock) lock=$target; break ;;
      esac
    done
    if [[ -n $lock ]]; then
      NESTED_DISPLAY=$(basename "$lock" .lock)
      break
    fi
    kill -0 "$NESTED_PID" 2>/dev/null || break
  done

  if [[ -z $NESTED_DISPLAY ]]; then
    echo "FAIL: nested compositor did not start" >&2
    tail -20 "$sandbox/hypr.log" >&2
    return 1
  fi
  # Refuse to touch the session running this script, whatever went wrong above.
  if [[ $NESTED_DISPLAY == "${WAYLAND_DISPLAY:-}" ]]; then
    echo "FAIL: refusing to run -- detected display $NESTED_DISPLAY is this session" >&2
    return 1
  fi
  sleep 2
  return 0
}
