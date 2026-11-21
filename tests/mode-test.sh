#!/usr/bin/env bash
# Runs the kiosk's sway config and packages/odimac/mode in a headless sway,
# with terminals standing in for Moonlight and the receiver. Needs sway,
# foot and jq; no hardware or root:  tests/mode-test.sh
set -u
for c in sway swaymsg foot jq; do
  command -v "$c" >/dev/null || { echo "skipped: $c is not installed"; exit 0; }
done
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'kill "$sway" 2>/dev/null; wait 2>/dev/null; rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/lib" "$t/run" "$t/home"; chmod 700 "$t/run"
cp "$here"/packages/odimac/{common.sh,mode,receiver-loop} "$t/lib/"
sed -i "s|/usr/lib/odimac|$t/lib|g" "$t/lib/receiver-loop"
printf 'GAME_MIN_SESSION=0\nMODE_IDLE_RETURN=0\nRECEIVER_NAME=test\n' > "$t/conf"
foot=$(command -v foot)
cat > "$t/bin/moonlight" <<S
#!/bin/sh
echo "\$*" >> "$t/moonlight.log"
exec $foot --app-id com.moonlight_stream.Moonlight sleep 600
S
cat > "$t/bin/od-receiver" <<S
#!/bin/sh
exec $foot --app-id od-receiver sleep 600
S
printf '#!/bin/sh\nshift 2\nexec "$@"\n' > "$t/bin/systemd-cat"
chmod +x "$t/bin/"*
# The config as shipped, without the parts that need the real machine.
sed -e "s|/usr/lib/odimac|$t/lib|g" -e '/powerd$/d' -e '/^include /d' \
  "$here/packages/odimac/sway.conf" > "$t/sway.conf"

export PATH="$t/bin:$PATH" HOME="$t/home" XDG_RUNTIME_DIR="$t/run" XDG_CONFIG_HOME="$t/home/.config"
export ODIMAC_CONF="$t/conf" ODIMAC_LIB="$t/lib" SWAYSOCK="$t/run/sway.sock"
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
unset WAYLAND_DISPLAY DISPLAY

fail=0
if ! sway --validate --config "$t/sway.conf" 2> "$t/validate.log"; then
  echo "FAIL the sway config does not validate"; cat "$t/validate.log"; exit 1
fi
echo "ok   the sway config validates"
sway --config "$t/sway.conf" 2> "$t/sway.log" &
sway=$!
for _ in $(seq 50); do [[ -S $SWAYSOCK ]] && break; sleep 0.2; done

focused() { swaymsg -t get_workspaces | jq -r '.[] | select(.focused) | .name'; }
where() { # app_id -> the workspaces holding such a window
  swaymsg -t get_tree | jq -r --arg a "$1" \
    '[.. | objects | select(.type == "workspace") | .name as $w | .. | objects | select(.app_id == $a) | $w] | unique | join(",")'
}
until_true() { local i; for i in $(seq 50); do "$@" && return 0; sleep 0.2; done; return 1; }
check() { # description, command...
  local d=$1; shift
  if until_true "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi
}
is() { [[ $($1 ${3:+"$3"}) == "$2" ]]; }
mode() { "$t/lib/mode" "$@"; }
# As the key bindings do: from inside the session, and not waited for.
bound() { swaymsg -q exec "$t/lib/mode $1"; }

check "starts on the display workspace"            is focused display
check "the receiver's window is on display"        is where display od-receiver
bound game
check "Ctrl+Alt+2's command shows the game workspace" is focused game
check "Moonlight's window is on game"              is where game com.moonlight_stream.Moonlight
check "the mode is recorded for powerd"            is "mode status" game
[[ $(< "$XDG_CONFIG_HOME/Moonlight Game Streaming Project/Moonlight.conf") == *width=2560*height=1440* ]] \
  && echo "ok   Moonlight starts out at 2560x1440" || { echo "FAIL Moonlight's settings were not seeded"; fail=1; }
pkill -f -- '--app-id od-receiver'
check "a restarted receiver still lands on display" is where display od-receiver
check "and does not take over the game workspace"  is focused game
mode display
check "back to display while Moonlight keeps running" is focused display
bound game
check "a second switch reuses the running Moonlight" is focused game
sleep 1
[[ $(wc -l < "$t/moonlight.log") == 1 ]] || { echo "FAIL Moonlight was started twice"; fail=1; }
pkill -f -- '--app-id com.moonlight_stream.Moonlight'
check "returns to display when Moonlight exits"    is focused display
check "and records that"                           is "mode status" display

printf 'GAME_HOST=pc.test\nGAME_MIN_SESSION=0\nMODE_IDLE_RETURN=0\n' > "$t/conf"
bound game
check "with GAME_HOST it streams directly"         grep -q '^stream pc.test Desktop --resolution 2560x1440 --fps 60' "$t/moonlight.log"
pkill -f -- '--app-id com.moonlight_stream.Moonlight'
check "and returns to display when the stream ends" is focused display
bound shell
check "the terminal opens on the shell workspace"  is where shell foot
check "and is showing"                             is focused shell
pkill -x foot

(( fail )) && { echo; tail -n 30 "$t/sway.log"; }
exit "$fail"
