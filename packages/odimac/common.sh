# Sourced by the odimac scripts: defaults, then the config file.
RECEIVER_NAME=""
RECEIVER_DEVICE="Mac"
RECEIVER_EXTRA_ARGS=""
PANEL_OFF_DELAY=60
SUSPEND_AFTER=0
BRIGHTNESS=""
PANEL_POWER_CYCLE=auto
RECEIVER_PORT=9000
ODIMAC_CONF="${ODIMAC_CONF:-/etc/odimac/odimac.conf}"
# shellcheck disable=SC1090
[[ -r "$ODIMAC_CONF" ]] && . "$ODIMAC_CONF"
: "${RECEIVER_NAME:=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo iMac)}"
