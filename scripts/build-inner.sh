#!/usr/bin/env bash
# Runs as root inside an Arch Linux container (see ../build.sh): builds the
# two packages into a local pacman repository, then the ISO from archiso's
# baseline profile plus iso/.
set -euo pipefail
: "${OPENDISPLAY_REPO:=https://github.com/peetzweg/opendisplay}"
: "${OPENDISPLAY_REF:=v1.30.3}"
# Kernel package to pin, from the Arch Linux Archive. The 5K panel driver
# (scripts/build-amdgpu5k.sh) supports the 7.1 and 7.2 series only. Set
# KERNEL_PKGVER=current for Arch's current kernel and the stock 4K driver.
: "${KERNEL_PKGVER:=7.2.11.arch1-1}"
SRC=/src OUT=/out WORK=/work REPO=/work/repo CACHE=/out/cache

# pacman's download sandbox (seccomp) fails under x86_64 emulation on Apple
# silicon ("error restricting syscalls via seccomp"). This is a throwaway
# build container, so turn it off: here for the container's own pacman, and
# below for the one mkarchiso runs. Neither file ends up in the image.
sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf

pacman -Syu --noconfirm --needed base-devel git archiso grub bc cpio pahole zstd kmod

useradd -m builder
cat > /etc/sudoers.d/builder <<'SUDO'
builder ALL=(ALL) NOPASSWD: ALL
Defaults env_keep += "HTTPS_PROXY HTTP_PROXY NO_PROXY https_proxy http_proxy no_proxy"
SUDO
mkdir -p "$WORK" "$REPO"
chown builder "$WORK" "$REPO"
as_builder() { sudo -u builder env PKGDEST="$REPO" "$@"; }

# The slow artifacts are kept in out/cache, keyed by everything they are built
# from, and reused by later builds.
recv_sha=$(git ls-remote "$OPENDISPLAY_REPO" "$OPENDISPLAY_REF" "$OPENDISPLAY_REF^{}" | tail -n1 | cut -c1-12)
[[ -n $recv_sha ]] || { echo "cannot resolve $OPENDISPLAY_REF in $OPENDISPLAY_REPO" >&2; exit 1; }
# Our changes to the receiver (patches/opendisplay/*.patch), applied on top.
# OPENDISPLAY_PATCHES=0 builds the source as it is.
patches=()
[[ ${OPENDISPLAY_PATCHES:-1} == 1 ]] && patches=("$SRC"/patches/opendisplay/*.patch)
[[ -e ${patches[0]:-} ]] || patches=()
patch_key=
(( ${#patches[@]} )) && patch_key=-p$(cat "${patches[@]}" | sha256sum | cut -c1-8)
recv_cache=$CACHE/receiver-$recv_sha$patch_key
if compgen -G "$recv_cache/*.pkg.tar.zst" >/dev/null; then
  echo "==> opendisplay-receiver $OPENDISPLAY_REF ($recv_sha$patch_key): cached"
else
  echo "==> opendisplay-receiver from $OPENDISPLAY_REPO @ $OPENDISPLAY_REF ($recv_sha)"
  as_builder git clone --depth 1 --branch "$OPENDISPLAY_REF" "$OPENDISPLAY_REPO" "$WORK/opendisplay"
  if (( ${#patches[@]} )); then
    echo "    with ${#patches[@]} patch(es) from patches/opendisplay"
    # from-checkout.sh packages the committed tree, so the patches are commits.
    as_builder git -C "$WORK/opendisplay" -c user.name=odimac -c user.email=odimac@localhost \
      am --quiet "${patches[@]}" || {
        echo "patches/opendisplay does not apply to $OPENDISPLAY_REF; set OPENDISPLAY_PATCHES=0 to build without" >&2
        exit 1
      }
  fi
  check=--nocheck
  [[ ${RECEIVER_CHECK:-} == 1 ]] && check=
  mkdir -p "$WORK/recv-out"; chown builder "$WORK/recv-out"
  (cd "$WORK/opendisplay/linux/packaging/arch/opendisplay-receiver" &&
    sudo -u builder env PKGDEST="$WORK/recv-out" ./from-checkout.sh --syncdeps --noconfirm $check)
  rm -rf "$recv_cache.tmp"; mkdir -p "$recv_cache.tmp"
  cp "$WORK"/recv-out/opendisplay-receiver-[0-9]*.pkg.tar.zst "$recv_cache.tmp/"
  mv "$recv_cache.tmp" "$recv_cache"
fi
cp "$recv_cache"/*.pkg.tar.zst "$REPO/"

echo "==> odimac"
cp -r "$SRC/packages/odimac" "$WORK/odimac"
chown -R builder "$WORK/odimac"
(cd "$WORK/odimac" && as_builder makepkg --force --nodeps)

extra_packages=()
if [[ $KERNEL_PKGVER != current ]]; then
  krel=${KERNEL_PKGVER/.arch/-arch}
  mkdir -p "$WORK/kernel"; chown builder "$WORK/kernel"
  # The two drivers are built against the pinned kernel's headers; only
  # needed when one of them is not in the cache.
  have_headers=0
  need_headers() {
    (( have_headers )) && return
    local archive=https://archive.archlinux.org/packages/l
    # pacman verifies the packages' signatures before installing them.
    pacman -U --noconfirm \
      "$archive/linux/linux-$KERNEL_PKGVER-x86_64.pkg.tar.zst" \
      "$archive/linux-headers/linux-headers-$KERNEL_PKGVER-x86_64.pkg.tar.zst"
    have_headers=1
  }

  echo "==> kernel $krel with the 5K panel driver"
  key=$(cat "$SRC/scripts/build-amdgpu5k.sh" "$SRC"/packages/odimac-amdgpu5k/* | sha256sum | cut -c1-12)
  k5_cache=$CACHE/amdgpu5k-$KERNEL_PKGVER-$key
  if compgen -G "$k5_cache/odimac-amdgpu5k-*.pkg.tar.zst" >/dev/null; then
    echo "    cached"
  else
    need_headers
    cp -r "$SRC/packages/odimac-amdgpu5k" "$WORK/odimac-amdgpu5k"
    printf '_krel=%s\n_pkgver=%s\n' "$krel" "$KERNEL_PKGVER" > "$WORK/odimac-amdgpu5k/krel"
    mkdir -p "$WORK/kernel" "$WORK/k5-out"
    chown -R builder "$WORK/odimac-amdgpu5k" "$WORK/kernel" "$WORK/k5-out"
    as_builder "$SRC/scripts/build-amdgpu5k.sh" "$krel" "$WORK/kernel" "$WORK/odimac-amdgpu5k/amdgpu.ko.zst"
    (cd "$WORK/odimac-amdgpu5k" && sudo -u builder env PKGDEST="$WORK/k5-out" makepkg --force --nodeps)
    rm -rf "$k5_cache.tmp"; mkdir -p "$k5_cache.tmp"
    cp "$WORK"/k5-out/*.pkg.tar.zst "/var/cache/pacman/pkg/linux-$KERNEL_PKGVER-x86_64.pkg.tar.zst" "$k5_cache.tmp/"
    mv "$k5_cache.tmp" "$k5_cache"
  fi
  cp "$k5_cache"/*.pkg.tar.zst "$REPO/"
  extra_packages+=(odimac-amdgpu5k)

  echo "==> sound driver (CS8409) for $krel"
  key=$(cat "$SRC/scripts/build-cs8409.sh" "$SRC"/packages/odimac-cs8409/* | sha256sum | cut -c1-12)
  cs_cache=$CACHE/cs8409-$KERNEL_PKGVER-$key
  if compgen -G "$cs_cache/odimac-cs8409-*.pkg.tar.zst" >/dev/null; then
    echo "    cached"
  else
    need_headers
    cp -r "$SRC/packages/odimac-cs8409" "$WORK/odimac-cs8409"
    printf '_krel=%s\n_pkgver=%s\n' "$krel" "$KERNEL_PKGVER" > "$WORK/odimac-cs8409/krel"
    mkdir -p "$WORK/cs-out"
    chown -R builder "$WORK/odimac-cs8409" "$WORK/cs-out"
    as_builder "$SRC/scripts/build-cs8409.sh" "$krel" "$WORK/kernel" "$WORK/odimac-cs8409/snd-hda-codec-cs8409.ko.zst"
    (cd "$WORK/odimac-cs8409" && sudo -u builder env PKGDEST="$WORK/cs-out" makepkg --force --nodeps)
    mkdir -p "$cs_cache.tmp"
    cp "$WORK"/cs-out/*.pkg.tar.zst "$cs_cache.tmp/"
    mv "$cs_cache.tmp" "$cs_cache"
  fi
  cp "$cs_cache"/*.pkg.tar.zst "$REPO/"
  extra_packages+=(odimac-cs8409)
fi

repo-add -q "$REPO/odimac.db.tar.gz" "$REPO"/*.pkg.tar.zst

echo "==> ISO profile"
profile=$WORK/profile
cp -r /usr/share/archiso/configs/baseline "$profile"
sed -i '/^\[options\]/a DisableSandbox' "$profile/pacman.conf"
cp -r "$SRC/iso/airootfs/." "$profile/airootfs/"
grep -v '^#' "$SRC/iso/packages.extra" >> "$profile/packages.x86_64"
printf '%s\n' "${extra_packages[@]}" >> "$profile/packages.x86_64"
# The image's own pacman.conf, for installing software on the iMac: Arch's
# default, and with the pinned kernel left out of `pacman -Syu`, which the 5K
# driver would otherwise block.
if [[ $KERNEL_PKGVER != current ]]; then
  sed -e '/^DisableSandbox$/d' -e 's/^#IgnorePkg .*/IgnorePkg   = linux linux-headers/' \
    /etc/pacman.conf > "$profile/airootfs/etc/pacman.conf"
  grep -q '^IgnorePkg' "$profile/airootfs/etc/pacman.conf" || { echo "could not set IgnorePkg in the image's pacman.conf" >&2; exit 1; }
fi
# Ahead of [core], so a pinned kernel in the local repository wins.
sed -i "0,/^\\[core\\]/s||[odimac]\\nSigLevel = Optional TrustAll\\nServer = file://$REPO\\n\\n[core]|" "$profile/pacman.conf"
grep -q '^\[odimac\]' "$profile/pacman.conf" || { echo "could not add the local repository to pacman.conf" >&2; exit 1; }
sed -i -e 's/^iso_name=.*/iso_name="odimac"/' \
       -e 's/^iso_application=.*/iso_application="OpenDisplay iMac appliance"/' \
       "$profile/profiledef.sh"
# Quiet boot straight into the display session.
# cow_spacesize: on the live stick, everything written (installed software
# included) is held in memory, 256M of it unless told otherwise.
quiet='quiet loglevel=3 systemd.show_status=false rd.udev.log_level=3 vt.global_cursor_default=0 cow_spacesize=50%'
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
cp "$REPO"/odimac-*.pkg.tar.zst "$OUT"/
ls -lh "$OUT"
