#!/usr/bin/env bash
# Runs as root inside an Arch Linux container (see ../build.sh): builds the
# two packages into a local pacman repository, then the ISO from archiso's
# baseline profile plus iso/.
set -euo pipefail
: "${OPENDISPLAY_REPO:=https://github.com/peetzweg/opendisplay}"
: "${OPENDISPLAY_REF:=v1.30.3}"
SRC=/src OUT=/out WORK=/work REPO=/work/repo

pacman -Syu --noconfirm --needed base-devel git archiso grub

useradd -m builder
cat > /etc/sudoers.d/builder <<'SUDO'
builder ALL=(ALL) NOPASSWD: ALL
Defaults env_keep += "HTTPS_PROXY HTTP_PROXY NO_PROXY https_proxy http_proxy no_proxy"
SUDO
mkdir -p "$WORK" "$REPO"
chown builder "$WORK" "$REPO"
as_builder() { sudo -u builder env PKGDEST="$REPO" "$@"; }

echo "==> opendisplay-receiver from $OPENDISPLAY_REPO @ $OPENDISPLAY_REF"
as_builder git clone --depth 1 --branch "$OPENDISPLAY_REF" "$OPENDISPLAY_REPO" "$WORK/opendisplay"
check=--nocheck
[[ ${RECEIVER_CHECK:-} == 1 ]] && check=
(cd "$WORK/opendisplay/linux/packaging/arch/opendisplay-receiver" &&
  as_builder ./from-checkout.sh --syncdeps --noconfirm $check)

echo "==> odimac"
cp -r "$SRC/packages/odimac" "$WORK/odimac"
chown -R builder "$WORK/odimac"
(cd "$WORK/odimac" && as_builder makepkg --force --nodeps)

repo-add -q "$REPO/odimac.db.tar.gz" "$REPO"/*.pkg.tar.zst

echo "==> ISO profile"
profile=$WORK/profile
cp -r /usr/share/archiso/configs/baseline "$profile"
cp -r "$SRC/iso/airootfs/." "$profile/airootfs/"
grep -v '^#' "$SRC/iso/packages.extra" >> "$profile/packages.x86_64"
cat >> "$profile/pacman.conf" <<CONF

[odimac]
SigLevel = Optional TrustAll
Server = file://$REPO
CONF
sed -i -e 's/^iso_name=.*/iso_name="odimac"/' \
       -e 's/^iso_application=.*/iso_application="OpenDisplay iMac appliance"/' \
       "$profile/profiledef.sh"
# Quiet boot straight into the display session.
quiet='quiet loglevel=3 systemd.show_status=false rd.udev.log_level=3 vt.global_cursor_default=0'
find "$profile/efiboot" -name '*.conf' -path '*entries*' -exec sed -i "/^options/ s/\$/ $quiet/" {} +
find "$profile" -name 'grub.cfg' -exec sed -i -E "/^\s*linux\s.*vmlinuz/ s/\$/ $quiet/" {} +
find "$profile/efiboot" -name loader.conf -exec sed -i 's/^timeout.*/timeout 2/' {} +
find "$profile" -name 'grub.cfg' -exec sed -i 's/^timeout=.*/timeout=2/' {} +
# The baseline profile is made for cloud and VM images: drop what an iMac
# does not need. tty1 belongs to the display session; odimac-install turns
# sshd on when given a key.
find "$profile/airootfs/etc/systemd/system" -type l \( -name 'cloud-*' -o -name 'hv_*' \
  -o -name 'vbox*' -o -name 'vm*' -o -name 'sshd.service' -o -name 'getty@tty1.service' \
  -o -name 'systemd-networkd-wait-online.service' \) -delete

mkarchiso -v -w "$WORK/iso" -o "$OUT" "$profile"
cp "$REPO"/*.pkg.tar.zst "$OUT"/
ls -lh "$OUT"
