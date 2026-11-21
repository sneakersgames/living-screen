# Sourced by the odimac scripts: defaults, then the config file.
RECEIVER_NAME=""
RECEIVER_DEVICE="Mac"
RECEIVER_DECODER="avdec_h264"
RECEIVER_HEVC=1
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

# --- load monitoring -------------------------------------------------------
# load_sample prints one line describing the time since its previous call:
# overall CPU use, the receiver's share, temperatures and fan speed. The
# first call only takes the baseline and prints nothing.
_load_cpu_total=0 _load_cpu_idle=0 _load_recv_ticks=0 _load_at=0
_hwmon_value() { # hwmon name, file glob -> first readable value
  local d f
  for d in /sys/class/hwmon/hwmon*; do
    [[ -r $d/name && $(<"$d/name") == "$1" ]] || continue
    for f in "$d"/$2; do
      [[ -r $f ]] && { cat "$f" 2>/dev/null && return 0; }
    done
  done
  return 1
}
load_sample() {
  local _ u n s i w q sq st total idle ticks=0 pid now out v
  read -r _ u n s i w q sq st _ < /proc/stat
  total=$((u + n + s + i + w + q + sq + st)) idle=$((i + w))
  pid=$(pgrep -x od-receiver | head -n1)
  if [[ -n $pid && -r /proc/$pid/stat ]]; then
    # utime and stime are fields 14 and 15; the name in field 2 has no spaces.
    read -r _ _ _ _ _ _ _ _ _ _ _ _ _ u s _ < "/proc/$pid/stat"
    ticks=$((u + s))
  fi
  now=$(date +%s)
  if (( _load_at > 0 && total > _load_cpu_total && now > _load_at )); then
    out="cpu $(( 100 - 100 * (idle - _load_cpu_idle) / (total - _load_cpu_total) ))%"
    if [[ -n $pid ]] && (( ticks >= _load_recv_ticks )); then
      out+=", receiver $(( 100 * (ticks - _load_recv_ticks) / $(getconf CLK_TCK) / (now - _load_at) ))% of one core"
    fi
    v=$(_hwmon_value coretemp 'temp1_input') && out+=", CPU $((v / 1000))°C"
    v=$(_hwmon_value amdgpu 'temp1_input') && out+=", GPU $((v / 1000))°C"
    v=$(_hwmon_value applesmc 'fan*_input') && out+=", fan $v rpm"
    echo "$out"
  fi
  _load_cpu_total=$total _load_cpu_idle=$idle _load_recv_ticks=$ticks _load_at=$now
}
