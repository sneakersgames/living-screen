#!/usr/bin/env bash
# Builds an amdgpu module that drives the iMac 5K panel at 5120x2880, for one
# exact Arch kernel, from kernel.org source plus the community patch stack of
# https://github.com/ahmadtv/omarchy-imac18-3 (wake the second panel half,
# present both halves as one display, keep them in sync).
#
#   build-amdgpu5k.sh KREL WORKDIR OUTFILE
#     KREL     kernel release whose headers are installed, e.g. 7.2.11-arch1-1
#     OUTFILE  where to write amdgpu.ko.zst
#
# Only the module is built, against the installed kernel's own config and
# symbol table. Every safety check aborts the build instead of producing a
# module that might load and misbehave.
set -euo pipefail
KREL=${1:?kernel release} WORK=${2:?work dir} OUT=${3:?output file}
PATCH_REPO=https://github.com/ahmadtv/omarchy-imac18-3
PATCH_COMMIT=f8f6ca8095074d7535cab01ff127b3ee07842bb9
# Applied in this order; sha256 pins the exact content.
PATCHES=(
  "imac5k-lean-core-7.2.x.patch fcdf2344cab8838d1b3f023c24f9480581ef6983a1e226e101403b9db443a527"
  "imac5k-stitch-layer-7.x.patch 7f6ca13ca4354305ac1dfe0d9a9e7783daed8375c1117836c13b384fc9f1bc0c"
  "imac5k-stitch-hide-slave.patch ce1600998f5bf8cf6c7746617528a9491d6a385022a094cc3c99d14b168281c2"
  "amdgpu-hpd-skip-during-reset.patch 4286fed046fd53077df1fb738629d9e443fa159fbca205dc09d54f5d4df78f9f"
  "amdgpu-vce-suspend-in-reset.patch 4e165abacc093b72cefb7c03672fa10d67c64369edcc9f0a06d9d63708bed6fe"
  "amdgpu-vce3-ring-align-mask.patch 66f08851a069027072127902dcec77dcf8369e1bc34d6d5dcdec481044512ddc"
)
die() { echo "build-amdgpu5k: $*" >&2; exit 1; }
say() { echo "==> $*"; }

KVER=${KREL%%-*}                 # 7.2.11
KSUFFIX=${KREL#"$KVER"}          # -arch1-1
HDR=/usr/lib/modules/$KREL/build
[[ -e $HDR/Module.symvers ]] || die "headers for $KREL are not installed"

mkdir -p "$WORK"; cd "$WORK"
if [[ ! -d patches-src ]]; then
  git clone -q "$PATCH_REPO" patches-src
fi
git -C patches-src checkout -q "$PATCH_COMMIT"
for entry in "${PATCHES[@]}"; do
  read -r name sum <<<"$entry"
  echo "$sum  patches-src/patches/$name" | sha256sum -c --quiet || die "$name does not match its pinned checksum"
done

src=linux-$KVER
if [[ ! -f $src.tar.xz ]]; then
  say "downloading kernel $KVER source"
  curl -fL --retry 3 -o "$src.tar.xz.part" "https://cdn.kernel.org/pub/linux/kernel/v${KVER%%.*}.x/$src.tar.xz"
  mv "$src.tar.xz.part" "$src.tar.xz"
fi
curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v${KVER%%.*}.x/sha256sums.asc" \
  | grep " $src.tar.xz\$" | sha256sum -c --quiet || die "$src.tar.xz does not match kernel.org's checksum"
rm -rf "$src"
say "extracting"
tar -xf "$src.tar.xz"
cd "$src"

# Same config, symbol versions and release string as the installed kernel.
cp "$HDR/.config" .config
cp "$HDR/Module.symvers" Module.symvers
printf '%s' "$KSUFFIX" > localversion
scripts/config --disable LOCALVERSION_AUTO --set-str LOCALVERSION ""
make olddefconfig >/dev/null
[[ $(make -s kernelrelease) == "$KREL" ]] || die "source builds as $(make -s kernelrelease), not $KREL"

for entry in "${PATCHES[@]}"; do
  read -r name _ <<<"$entry"
  p=../patches-src/patches/$name
  # Already part of this kernel version (a backported fix): skip.
  if patch -p1 -R --dry-run --force --fuzz=0 < "$p" >/dev/null 2>&1; then
    say "$name: already in $KVER"
    continue
  fi
  # No fuzz: a hunk that no longer matches exactly must stop the build.
  patch -p1 --dry-run --force --fuzz=0 < "$p" >/dev/null || die "$name does not apply cleanly to $KVER"
  say "applying $name"
  patch -p1 --fuzz=0 --quiet < "$p"
done

# Arch's kernel is kernel.org plus a few patches. The module is only safe if
# every header it compiles against is the one the kernel was built with.
say "comparing headers with the installed $KREL"
hdrdiff=$(for d in include arch/x86/include; do
  diff -rq --exclude=generated --exclude=config "$d" "$HDR/$d"
done 2>&1 || true)
[[ -z $hdrdiff ]] || { echo "$hdrdiff" | head -n 12 >&2; die "kernel headers differ from the source"; }

say "building the amdgpu module (the slow part)"
make modules_prepare >/dev/null
make -j"$(nproc)" M=drivers/gpu/drm/amd/amdgpu modules >/dev/null
ko=drivers/gpu/drm/amd/amdgpu/amdgpu.ko
[[ -f $ko ]] || die "no module was built"
vm=$(modinfo -F vermagic "$ko" | awk '{print $1}')
[[ $vm == "$KREL" ]] || die "module is for '$vm', not $KREL"
modinfo -F parm "$ko" | grep -q '^tiled_stitch:' || die "module lacks the tiled_stitch parameter"
strip --strip-debug "$ko"
mkdir -p "$(dirname "$OUT")"
zstd -q -f -19 "$ko" -o "$OUT"
say "built $OUT ($(modinfo -F srcversion "$ko"), vermagic $vm)"
