#!/usr/bin/env bash
# Runs as root inside an Arch Linux container (see ../build.sh): makes the
# container an Omarchy as far as packages go (Omarchy's package repository,
# its snapshot of Arch's, its kernel), then builds the packages with
# build-packages.sh. What is built here therefore fits an iMac running the
# same Omarchy channel, updated to the same day.
set -euo pipefail
: "${OMARCHY_CHANNEL:=stable}"
SRC=/src OUT=/out
# The key Omarchy signs its packages with (default/pacman/keys in its source).
OMARCHY_KEY=68B3537F39A313B3E574D06777193F152BDBE6A6
OMARCHY_KEY_URL=https://raw.githubusercontent.com/basecamp/omarchy/HEAD/default/pacman/keys/$OMARCHY_KEY.asc

case $OMARCHY_CHANNEL in
  stable) mirror=https://stable-mirror.omarchy.org ;;
  rc)     mirror=https://rc-mirror.omarchy.org ;;
  edge)   mirror=https://mirror.omarchy.org ;;
  *) echo "OMARCHY_CHANNEL is stable, rc or edge" >&2; exit 1 ;;
esac

# Omarchy's pacman.conf for this channel. DisableSandbox: pacman's download
# sandbox (seccomp) fails under x86_64 emulation on Apple silicon, and this
# is a throwaway container.
cat > /etc/pacman.conf <<CONF
[options]
HoldPkg = pacman glibc
Architecture = auto
ParallelDownloads = 5
DisableSandbox
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[omarchy]
Server = https://pkgs.omarchy.org/$OMARCHY_CHANNEL/\$arch

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
CONF
echo "Server = $mirror/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist

pacman-key --init
pacman-key --populate archlinux
curl -fsSL --retry 3 -o /tmp/omarchy.asc "$OMARCHY_KEY_URL"
got=$(gpg --show-keys --with-colons /tmp/omarchy.asc | awk -F: '$1 == "fpr" { print $10; exit }')
[[ $got == "$OMARCHY_KEY" ]] || { echo "the Omarchy signing key is not the one expected ($got)" >&2; exit 1; }
pacman-key --add /tmp/omarchy.asc
pacman-key --lsign-key "$OMARCHY_KEY"

# -uu: the container image is newer than Omarchy's snapshot of Arch.
pacman -Syyuu --noconfirm
pacman -S --noconfirm --needed base-devel git sudo linux-omarchy linux-omarchy-headers

useradd -m builder
cat > /etc/sudoers.d/builder <<'SUDO'
builder ALL=(ALL) NOPASSWD: ALL
Defaults env_keep += "HTTPS_PROXY HTTP_PROXY NO_PROXY https_proxy http_proxy no_proxy"
SUDO
mkdir -p /work "$OUT/cache"
chown builder /work
owner=$(stat -c %u:%g "$OUT")
chown -R builder "$OUT"
# Whatever happens, the output directory goes back to whoever owns it.
trap 'chown -R "$owner" "$OUT"' EXIT

sudo -u builder env WORK=/work CACHE="$OUT/cache" \
  KREL="${KREL:-}" OPENDISPLAY_REPO="${OPENDISPLAY_REPO:-}" OPENDISPLAY_REF="${OPENDISPLAY_REF:-}" \
  OPENDISPLAY_PATCHES="${OPENDISPLAY_PATCHES:-1}" RECEIVER_CHECK="${RECEIVER_CHECK:-}" \
  HTTPS_PROXY="${HTTPS_PROXY:-}" HTTP_PROXY="${HTTP_PROXY:-}" NO_PROXY="${NO_PROXY:-}" \
  https_proxy="${https_proxy:-}" http_proxy="${http_proxy:-}" no_proxy="${no_proxy:-}" \
  "$SRC/scripts/build-packages.sh" "$OUT"
