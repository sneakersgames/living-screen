#!/usr/bin/env bash
# The mode switching of the one Hyprland session, without Hyprland:
#   - packages/odimac/hyprland.lua, driven by tests/session-test.lua against
#     a stand-in for Hyprland's Lua API (needs lua; skipped without it)
#   - the scripts that talk to it (mode, game), with hyprctl and moonlight
#     stubbed
# No hardware or root:  tests/session-test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/lib" "$t/run" "$t/home"
fail=0
check() { # description, command...
  local d=$1; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi
}

lua=$(command -v lua || command -v lua5.4 || true)
if [[ -n $lua ]]; then
  ODIMAC_RUN="$t/run" HOME="$t/home" "$lua" "$here/tests/session-test.lua" "$here/packages/odimac/hyprland.lua" || fail=1
  rm -f "$t/run"/odimac-*
else
  echo "skipped: the config's logic (lua is not installed)"
fi

cp "$here"/packages/odimac/{common.sh,mode,game} "$t/lib/"
cat > "$t/bin/hyprctl" <<S
#!/bin/sh
echo "\$*" >> "$t/hyprctl.log"
echo ok
S
cat > "$t/bin/moonlight" <<S
#!/bin/sh
echo "\$*" >> "$t/moonlight.log"
S
chmod +x "$t/bin/"*
: > "$t/hyprctl.log"; : > "$t/moonlight.log"
printf 'GAME_MIN_SESSION=0\n' > "$t/conf"
export PATH="$t/bin:$PATH" HOME="$t/home" XDG_CONFIG_HOME="$t/home/.config" XDG_RUNTIME_DIR="$t/run"
export ODIMAC_CONF="$t/conf" ODIMAC_LIB="$t/lib" ODIMAC_RUN="$t/run" HYPRLAND_INSTANCE_SIGNATURE=test

"$t/lib/mode" game
check "mode game asks the session for gaming" grep -qxF 'eval return odimac.mode("game")' "$t/hyprctl.log"
echo desktop > "$t/run/odimac-mode"
check "mode status reads what the session recorded" test "$("$t/lib/mode" status)" = desktop
"$t/lib/mode" bogus 2>/dev/null; check "mode refuses an unknown mode" test $? -eq 2

: > "$t/hyprctl.log"
"$t/lib/game" 2>/dev/null
check "game opens Moonlight" test "$(wc -l < "$t/moonlight.log")" -eq 1
check "tells the session whose windows they are" grep -qE '^eval odimac\.pid\([0-9]+, "game"\)$' "$t/hyprctl.log"
check "and that it has ended" grep -qxF 'eval odimac.ended("game")' "$t/hyprctl.log"
check "Moonlight starts out at 2560x1440" grep -q 'width=2560' "$XDG_CONFIG_HOME/Moonlight Game Streaming Project/Moonlight.conf"
printf 'GAME_HOST=pc.test\nGAME_MIN_SESSION=0\n' > "$t/conf"
: > "$t/moonlight.log"
"$t/lib/game" 2>/dev/null
check "with GAME_HOST it streams directly" grep -q '^stream pc.test Desktop --resolution 2560x1440 --fps 60' "$t/moonlight.log"
printf 'GAME_HOST=pc.test\nGAME_MIN_SESSION=5\n' > "$t/conf"
: > "$t/moonlight.log"
"$t/lib/game" 2>/dev/null
check "a stream that ends at once is followed by Moonlight's own window" test "$(wc -l < "$t/moonlight.log")" -eq 2

exit "$fail"
