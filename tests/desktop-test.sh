#!/usr/bin/env bash
# Checks the session's configuration as far as that goes without a graphics
# card: Hyprland parses its config (which also checks the arguments of every
# dispatcher in it), and the Quickshell bar loads in a
# headless sway. Needs Hyprland, quickshell and sway; skips itself without
# them, and as root (Hyprland refuses to run):  tests/desktop-test.sh
set -u
for c in Hyprland qs sway; do
  command -v "$c" >/dev/null || { echo "skipped: $c is not installed"; exit 0; }
done
(( EUID )) || { echo "skipped: run as a regular user"; exit 0; }
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'kill "$sway" "$qs" 2>/dev/null; wait 2>/dev/null; rm -rf "$t"' EXIT
sway='' qs=''
mkdir -p "$t/run" "$t/home"; chmod 700 "$t/run"
export HOME="$t/home" XDG_RUNTIME_DIR="$t/run"
unset WAYLAND_DISPLAY DISPLAY SWAYSOCK HYPRLAND_INSTANCE_SIGNATURE
fail=0

(cd "$t" && Hyprland --verify-config --config "$here/packages/odimac/hyprland.lua") > "$t/hypr.log" 2>&1
if grep -qx 'config ok' "$t/hypr.log" && ! grep -q 'Lua error' "$t/hypr.log"; then
  echo "ok   Hyprland accepts hyprland.lua"
else
  echo "FAIL Hyprland rejects hyprland.lua"; grep -v DEBUG "$t/hypr.log"; fail=1
fi

export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
: > "$t/sway.conf"
sway --config "$t/sway.conf" 2> "$t/sway.log" & sway=$!
for _ in $(seq 50); do
  WAYLAND_DISPLAY=$(cd "$t/run" && ls | grep -E '^wayland-[0-9]+$' | head -n1)
  [[ -n $WAYLAND_DISPLAY ]] && break; sleep 0.2
done
export WAYLAND_DISPLAY QT_QUICK_BACKEND=software
qs -p "$here/packages/odimac/shell.qml" > "$t/qs.log" 2>&1 & qs=$!
for _ in $(seq 50); do grep -qE 'Configuration Loaded|ERROR.*(qml|shell)' "$t/qs.log" && break; sleep 0.2; done
# Without Hyprland and PipeWire running, those two say so; anything else is ours.
if grep -q 'Configuration Loaded' "$t/qs.log" && ! grep -E 'shell\.qml|ReferenceError|TypeError' "$t/qs.log" | grep -v 'Launching config'; then
  echo "ok   Quickshell loads the bar"
else
  echo "FAIL Quickshell does not load the bar"; cat "$t/qs.log"; fail=1
fi
exit "$fail"
