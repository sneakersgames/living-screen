#!/usr/bin/env bash
# Exercises packages/odimac/powerd against a fake sysfs and stubbed
# swaymsg/ss/systemctl. No hardware or root needed:  tests/powerd-test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'kill "$pid" 2>/dev/null; rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/lib" "$t/run" "$t/sys/class/net/lo"
cp "$here/packages/odimac/common.sh" "$t/lib/"
printf 'PANEL_OFF_DELAY=3\nSUSPEND_AFTER=6\n' > "$t/conf"
cat > "$t/bin/swaymsg" <<S
#!/bin/sh
echo "\$*" >> "$t/panel.log"
S
cat > "$t/bin/ss" <<S
#!/bin/sh
[ -e "$t/session" ] && echo "10.0.0.1:9000 10.0.0.2:5555"
exit 0
S
cat > "$t/bin/systemctl" <<S
#!/bin/sh
echo "\$*" >> "$t/systemctl.log"
S
chmod +x "$t/bin/"*
: > "$t/panel.log"; : > "$t/systemctl.log"

PATH="$t/bin:$PATH" ODIMAC_CONF="$t/conf" ODIMAC_LIB="$t/lib" ODIMAC_SYSFS="$t/sys" ODIMAC_RUN="$t/run" \
  ODIMAC_POLL=0.2 ODIMAC_LOAD_INTERVAL=2 "$here/packages/odimac/powerd" 2> "$t/powerd.log" &
pid=$!

fail=0
panel() { tail -n1 "$t/panel.log" | awk '{print $NF}'; }
expect() { # description, expected panel state
  if [[ $(panel) == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: panel is '$(panel)', want '$2'"; fail=1; fi
}

sleep 1;   expect "lit after start" on
sleep 3.5; expect "dark once idle" off
mkdir "$t/sys/class/net/thunderbolt0"
sleep 1;   expect "lit when the cable is plugged in" on
touch "$t/session"
sleep 4.5; expect "stays lit during a session, past the idle delay" on
if grep -q '^load: cpu ' "$t/powerd.log"; then echo "ok   logs the load during a session"
else echo "FAIL no load line during the session"; fail=1; fi
rm "$t/session"
sleep 1.5; expect "still lit just after the session ends" on
sleep 3;   expect "dark after the session ended" off
echo game > "$t/run/odimac-mode"
sleep 1;   expect "lit in gaming mode" on
sleep 3.5; expect "stays lit in gaming mode, past the idle delay" on
echo display > "$t/run/odimac-mode"
sleep 1.5; expect "still lit just after returning to display mode" on
sleep 3;   expect "dark once display mode is idle again" off
sleep 4
if [[ -s $t/systemctl.log ]]; then echo "FAIL suspended with the cable plugged in"; fail=1
else echo "ok   no suspend while the cable is plugged in"; fi
rmdir "$t/sys/class/net/thunderbolt0"
sleep 8
if grep -qx suspend "$t/systemctl.log"; then echo "ok   suspends once the cable has been out long enough"
else echo "FAIL no suspend after the cable was removed"; fail=1; fi

(( fail )) && { echo; cat "$t/powerd.log"; }
exit "$fail"
