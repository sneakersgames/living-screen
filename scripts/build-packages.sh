#!/usr/bin/env bash
# Builds the packages, on Omarchy itself or in the build container
# (build-inner.sh). Run as a regular user who may use sudo; nothing is
# installed except what the builds need.
#
#   build-packages.sh OUTDIR
#
#   KREL               kernel release to build the two drivers for (default:
#                      the installed linux-omarchy; "none" leaves them out)
#   WORK               scratch directory (default: OUTDIR/work), about 8 GB
#   CACHE              where finished packages are kept and found again
#                      (default: OUTDIR/cache)
#   OPENDISPLAY_REPO, OPENDISPLAY_REF, OPENDISPLAY_PATCHES, RECEIVER_CHECK
#                      see ../build.sh
set -euo pipefail
OUT=$(mkdir -p "${1:?output directory}" && cd "$1" && pwd)
SRC=$(cd "$(dirname "$0")/.." && pwd)
: "${OPENDISPLAY_REPO:=https://github.com/peetzweg/opendisplay}"
: "${OPENDISPLAY_REF:=v1.30.3}"
: "${WORK:=$OUT/work}"
: "${CACHE:=$OUT/cache}"
die() { echo "build-packages: $*" >&2; exit 1; }
(( EUID )) || die "run this as a regular user (makepkg refuses to run as root)"
mkdir -p "$WORK" "$CACHE"

# The kernel to build the drivers for: Omarchy's, as installed. After an
# update that is the new one, before it has been started.
if [[ -z ${KREL:-} ]]; then
  KREL=none
  for f in /usr/lib/modules/*/pkgbase; do
    [[ -e $f && $(<"$f") == linux-omarchy ]] && KREL=$(basename "$(dirname "$f")")
  done
  [[ $KREL != none ]] || echo "==> no linux-omarchy kernel is installed here: building without the two drivers"
fi

sudo pacman -S --noconfirm --needed base-devel git bc cpio pahole zstd kmod

# The slow artifacts are kept in the cache, keyed by everything they are
# built from, and reused by later builds.
recv_sha=$(git ls-remote "$OPENDISPLAY_REPO" "$OPENDISPLAY_REF" "$OPENDISPLAY_REF^{}" | tail -n1 | cut -c1-12)
[[ -n $recv_sha ]] || die "cannot resolve $OPENDISPLAY_REF in $OPENDISPLAY_REPO"
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
  rm -rf "$WORK/opendisplay" "$WORK/recv-out"
  git clone --depth 1 --branch "$OPENDISPLAY_REF" "$OPENDISPLAY_REPO" "$WORK/opendisplay"
  if (( ${#patches[@]} )); then
    echo "    with ${#patches[@]} patch(es) from patches/opendisplay"
    # from-checkout.sh packages the committed tree, so the patches are commits.
    git -C "$WORK/opendisplay" -c user.name=odimac -c user.email=odimac@localhost \
      am --quiet "${patches[@]}" || die "patches/opendisplay does not apply to $OPENDISPLAY_REF; set OPENDISPLAY_PATCHES=0 to build without"
  fi
  check=--nocheck
  [[ ${RECEIVER_CHECK:-} == 1 ]] && check=
  mkdir -p "$WORK/recv-out"
  # shellcheck disable=SC2086
  (cd "$WORK/opendisplay/linux/packaging/arch/opendisplay-receiver" &&
    PKGDEST="$WORK/recv-out" ./from-checkout.sh --syncdeps --noconfirm $check)
  rm -rf "$recv_cache.tmp"; mkdir -p "$recv_cache.tmp"
  cp "$WORK"/recv-out/opendisplay-receiver-[0-9]*.pkg.tar.zst "$recv_cache.tmp/"
  mv "$recv_cache.tmp" "$recv_cache"
fi

echo "==> odimac"
rm -rf "$WORK/odimac" "$WORK/odimac-out"
cp -r "$SRC/packages/odimac" "$WORK/odimac"
mkdir -p "$WORK/odimac-out"
(cd "$WORK/odimac" && PKGDEST="$WORK/odimac-out" makepkg --force --nodeps)

driver_caches=()
# driver NAME BUILD-SCRIPT MODULE-FILE CACHE-KEY: builds packages/NAME around
# the module that BUILD-SCRIPT makes for $KREL.
driver() {
  local name=$1 script=$2 module=$3 key=$4 cache
  cache=$CACHE/$name-$KREL-$key
  driver_caches+=("$cache")
  if compgen -G "$cache/$name-*.pkg.tar.zst" >/dev/null; then
    echo "    cached"
    return
  fi
  rm -rf "${WORK:?}/${name:?}" "${WORK:?}/${name:?}-out"
  cp -r "$SRC/packages/$name" "$WORK/$name"
  printf '_krel=%s\n_pkgbase=%s\n' "$KREL" "$(<"/usr/lib/modules/$KREL/pkgbase")" > "$WORK/$name/krel"
  mkdir -p "$WORK/kernel" "$WORK/$name-out"
  "$script" "$KREL" "$WORK/kernel" "$WORK/$name/$module"
  (cd "$WORK/$name" && PKGDEST="$WORK/$name-out" makepkg --force --nodeps)
  rm -rf "$cache.tmp"; mkdir -p "$cache.tmp"
  cp "$WORK/$name-out"/*.pkg.tar.zst "$cache.tmp/"
  mv "$cache.tmp" "$cache"
}

if [[ $KREL != none ]]; then
  [[ -e /usr/lib/modules/$KREL/build/Module.symvers ]] ||
    die "the headers of kernel $KREL are not installed. Update Omarchy first, so that kernel and headers are of one version; then: sudo pacman -S linux-omarchy-headers"
  echo "==> 5K panel driver for kernel $KREL"
  driver odimac-amdgpu5k "$SRC/scripts/build-amdgpu5k.sh" amdgpu.ko.zst \
    "$(cat "$SRC"/scripts/{build-amdgpu5k,kernel-source}.sh "$SRC"/packages/odimac-amdgpu5k/* \
       "$SRC"/patches/amdgpu/*.patch "$SRC"/patches/amdgpu/*/*.patch | sha256sum | cut -c1-12)"
  echo "==> sound driver (CS8409) for kernel $KREL"
  driver odimac-cs8409 "$SRC/scripts/build-cs8409.sh" snd-hda-codec-cs8409.ko.zst \
    "$(cat "$SRC"/scripts/{build-cs8409,kernel-source}.sh "$SRC"/packages/odimac-cs8409/* | sha256sum | cut -c1-12)"
fi

# The packages of this build, and of no earlier one.
rm -f "$OUT"/*.pkg.tar.zst
cp "$recv_cache"/*.pkg.tar.zst "$WORK"/odimac-out/*.pkg.tar.zst "$OUT/"
for c in "${driver_caches[@]}"; do cp "$c"/*.pkg.tar.zst "$OUT/"; done
echo "==> packages in $OUT"
ls -lh "$OUT"/*.pkg.tar.zst
