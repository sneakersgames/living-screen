#!/usr/bin/env bash
# odimac-setup against a scratch home, with sudo, ufw, systemctl, nmcli and
# hyprctl stubbed: what it adds to the user's Hyprland configuration, that a
# second run adds nothing, and that `remove` leaves the file as it was.
# No hardware; as root it runs the script as "nobody":  tests/setup-test.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/home/.config/hypr" "$t/share"
fail=0
check() { # description, command...
  local d=$1; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi
}
for c in ufw systemctl nmcli hyprctl tee rm; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/calls.log"\n' "$c" "$t" > "$t/bin/$c"
done
# sudo runs the stub of whatever it is given.
printf '#!/bin/sh\nexec "$@"\n' > "$t/bin/sudo"
chmod +x "$t/bin/"*
: > "$t/calls.log"
cp "$here/packages/odimac/hyprland.lua" "$t/share/"
printf -- '-- my Hyprland configuration\nrequire("default.hypr.omarchy")\n' > "$t/home/.config/hypr/hyprland.lua"
cp "$t/home/.config/hypr/hyprland.lua" "$t/before.lua"
chmod -R a+rwX "$t"

setup() {
  local run=(env PATH="$t/bin:$PATH" HOME="$t/home" USER=tester XDG_CONFIG_HOME="$t/home/.config"
    ODIMAC_SHARE="$t/share" HYPRLAND_INSTANCE_SIGNATURE=test "$here/packages/odimac/odimac-setup" "$@")
  if (( EUID )); then "${run[@]}"; else runuser -u nobody -- "${run[@]}"; fi
}
if (( EUID == 0 )) && ! command -v runuser >/dev/null; then
  echo "skipped: as root this needs runuser"; exit 0
fi
cfg=$t/home/.config/hypr/hyprland.lua

setup > "$t/out.log" 2>&1; check "sets up" test $? -eq 0
check "the configuration loads ours, after the user's own" test "$(grep -c -F "$t/share/hyprland.lua" "$cfg")" -eq 1
check "and keeps what was there" grep -qxF 'require("default.hypr.omarchy")' "$cfg"
lua=$(command -v lua || command -v lua5.4 || true)
if [[ -n $lua ]]; then
  # The added line must be Lua that survives our file being absent or broken.
  printf 'error("boom")\n' > "$t/share/broken.lua"
  sed "s|$t/share/hyprland.lua|$t/share/broken.lua|" "$cfg" | grep -F broken.lua > "$t/line.lua"
  check "a mistake in our file cannot break the user's configuration" bash -c '"$0" "$1" >/dev/null' "$lua" "$t/line.lua"
fi
check "lets the cable through Omarchy's firewall" grep -q '^ufw allow in on thunderbolt0 ' "$t/calls.log"
check "keeps the receiver off other networks" grep -qxF 'systemctl enable --now odimac-firewall.service' "$t/calls.log"
check "starts it in the running session" grep -qxF 'systemctl --user restart odimac.target' "$t/calls.log"
check "does not touch the login without being asked" bash -c "! grep -q autologin '$t/calls.log'"
setup > /dev/null 2>&1
check "a second run adds nothing" test "$(grep -c -F "$t/share/hyprland.lua" "$cfg")" -eq 1
setup --autologin > /dev/null 2>&1
check "--autologin writes the login manager's file" grep -q '^tee /etc/sddm.conf.d/odimac-autologin.conf' "$t/calls.log"
setup remove > /dev/null 2>&1; check "removes" test $? -eq 0
check "the configuration is as it was, but for a blank line" diff -q -B "$t/before.lua" "$cfg"
check "the firewall rule is taken back" grep -q '^ufw delete allow in on thunderbolt0' "$t/calls.log"
setup bogus > /dev/null 2>&1; check "refuses an unknown argument" test $? -eq 2
(( fail )) && cat "$t/out.log" "$t/calls.log"
exit "$fail"
