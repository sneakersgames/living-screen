#!/usr/bin/env bash
# Builds the sound driver for the 2017 iMac's audio chip (Cirrus CS8409 with
# a CS42L83), for one exact Arch kernel. The kernel's own snd-hda-codec-cs8409
# finds no speaker output on this board; this one, from
# https://github.com/jackdanyell/imac18-3-cs8409-linux-audio (after David
# Jones's snd_hda_macbookpro), replaces it.
#
#   build-cs8409.sh KREL WORKDIR OUTFILE
#     KREL     kernel release whose headers are installed, e.g. 7.2.11-arch1-1
#     WORKDIR  shared with build-amdgpu5k.sh, whose kernel source is reused
#     OUTFILE  where to write snd-hda-codec-cs8409.ko.zst
#
# Follows that repository's install.cirrus.driver.sh for kernels from 6.17
# on, without its downloads and without installing anything.
set -euo pipefail
KREL=${1:?kernel release} WORK=${2:?work dir} OUT=${3:?output file}
DRIVER_REPO=https://github.com/jackdanyell/imac18-3-cs8409-linux-audio
DRIVER_COMMIT=be90113a7638eb264b2ff5acfe888cd72c8364c6
die() { echo "build-cs8409: $*" >&2; exit 1; }
say() { echo "==> $*"; }

KVER=${KREL%%-*}
HDR=/usr/lib/modules/$KREL/build
[[ -e $HDR/Module.symvers ]] || die "headers for $KREL are not installed"

mkdir -p "$WORK"; cd "$WORK"
[[ -d cs8409-src ]] || git clone -q "$DRIVER_REPO" cs8409-src
git -C cs8409-src checkout -q -f "$DRIVER_COMMIT"
git -C cs8409-src clean -fdxq

src=linux-$KVER
if [[ ! -f $src.tar.xz ]]; then
  say "downloading kernel $KVER source"
  curl -fL --retry 3 -o "$src.tar.xz.part" "https://cdn.kernel.org/pub/linux/kernel/v${KVER%%.*}.x/$src.tar.xz"
  mv "$src.tar.xz.part" "$src.tar.xz"
fi
curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v${KVER%%.*}.x/sha256sums.asc" \
  | grep " $src.tar.xz\$" | sha256sum -c --quiet || die "$src.tar.xz does not match kernel.org's checksum"

cd cs8409-src
mkdir build
say "extracting the kernel's sound/hda"
tar --strip-components=2 -xf "../$src.tar.xz" -C build "$src/sound/hda"
hda=build/hda
cp makefiles/Makefile "$hda/Makefile"
cp makefiles/Makefile_common "$hda/common/Makefile"
cp makefiles/Makefile_codecs "$hda/codecs/Makefile"
cp makefiles/Makefile_cirrus "$hda/codecs/cirrus/Makefile"
cp patch_cirrus/cirrus_apple.h patch_cirrus/patch_cirrus_boot84.h patch_cirrus/patch_cirrus_new84.h \
  patch_cirrus/patch_cirrus_real84.h patch_cirrus/patch_cirrus_hda_generic_copy.h \
  patch_cirrus/patch_cirrus_real84_i2c.h "$hda/codecs/cirrus/"
# The patches are written for 6.17 and need patch's usual tolerance (offsets,
# two lines of fuzz) on later kernels, as in the repository's own installer.
# A hunk that fails outright stops the build.
for p in patch_cs8409.c.diff patch_cs8409.h.diff; do
  patch -d "$hda" -p1 --force < "$p" | sed 's/^/    /'
  [[ ${PIPESTATUS[0]} == 0 ]] || die "$p does not apply to $KVER"
done

say "building the cs8409 module"
# The flags of the repository's own Makefile.
make -C "$HDR" M="$PWD/$hda" modules >/dev/null \
  CFLAGS_MODULE="-DAPPLE_PINSENSE_FIXUP -DAPPLE_CODECS -DCONFIG_SND_HDA_RECONFIG=1 -Wno-unused-variable -Wno-unused-function"
ko=$hda/codecs/cirrus/snd-hda-codec-cs8409.ko
[[ -f $ko ]] || die "no module was built"
vm=$(modinfo -F vermagic "$ko" | awk '{print $1}')
[[ $vm == "$KREL" ]] || die "module is for '$vm', not $KREL"
strip --strip-debug "$ko"
mkdir -p "$(dirname "$OUT")"
zstd -q -f -19 "$ko" -o "$OUT"
say "built $OUT ($(modinfo -F srcversion "$ko"), vermagic $vm)"
