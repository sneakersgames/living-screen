#!/usr/bin/env bash
# Builds an amdgpu module that drives the iMac 5K panel at 5120x2880, for one
# exact installed kernel (Omarchy's linux-omarchy, or Arch's linux), from
# that kernel's own source (scripts/kernel-source.sh) plus the community
# patch stack of https://github.com/ahmadtv/omarchy-imac18-3 (wake the second
# panel half, present both halves as one display, keep them in sync).
#
#   build-amdgpu5k.sh KREL WORKDIR OUTFILE
#     KREL     kernel release whose headers are installed, e.g. 7.2.15-5-omarchy
#     OUTFILE  where to write amdgpu.ko.zst
#
# Only the module is built, against the installed kernel's own config and
# symbol table. Every safety check aborts the build instead of producing a
# module that might load and misbehave.
set -euo pipefail
KREL=${1:?kernel release} WORK=${2:?work dir} OUT=${3:?output file}
HERE=$(cd "$(dirname "$0")" && pwd)
# Our own fixes to the patched driver, applied last (patches/amdgpu/*.patch).
# A directory in there named after the kernel package (linux-omarchy) holds
# patches of the stack below as re-diffed for that kernel, for where the
# original no longer matches it line for line.
OWN_PATCHES=$(cd "$HERE/../patches/amdgpu" 2>/dev/null && pwd || true)
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

KVER=${KREL%%-*}                 # 7.2.15
KSUFFIX=${KREL#"$KVER"}          # -5-omarchy
HDR=/usr/lib/modules/$KREL/build
[[ -e $HDR/Module.symvers ]] || die "headers for $KREL are not installed"
PKGBASE=$(cat "/usr/lib/modules/$KREL/pkgbase" 2>/dev/null || echo linux)
case $PKGBASE in linux-omarchy*) FLAVOUR=linux-omarchy ;; *) FLAVOUR=$PKGBASE ;; esac
# The patches are written for these series; another needs them ported first.
case $KVER in 7.1.*|7.2.*) ;; *) die "the 5K patches are for kernels 7.1 and 7.2, not $KVER" ;; esac

mkdir -p "$WORK"; cd "$WORK"
if [[ ! -d patches-src ]]; then
  git clone -q "$PATCH_REPO" patches-src
fi
git -C patches-src checkout -q "$PATCH_COMMIT"
for entry in "${PATCHES[@]}"; do
  read -r name sum <<<"$entry"
  echo "$sum  patches-src/patches/$name" | sha256sum -c --quiet || die "$name does not match its pinned checksum"
done

"$HERE/kernel-source.sh" "$KREL" "$WORK"
src=amdgpu-$KREL
rm -rf "$src"
say "copying the kernel source"
cp -a --reflink=auto "base-$KREL" "$src"
cd "$src"

# Same config, symbol versions and release string as the installed kernel.
cp "$HDR/.config" .config
cp "$HDR/Module.symvers" Module.symvers
if [[ -e .odimac-plain ]]; then
  printf '%s' "$KSUFFIX" > localversion
  scripts/config --set-str LOCALVERSION ""
fi
scripts/config --disable LOCALVERSION_AUTO
make olddefconfig >/dev/null
[[ $(make -s kernelrelease) == "$KREL" ]] || die "source builds as $(make -s kernelrelease), not $KREL"
# olddefconfig drops what this machine's tools cannot build (Rust without a
# Rust compiler, for one). Said here because a module built with other
# options than its kernel is the first thing to look at if it misbehaves.
drift=$(diff <(grep '^CONFIG_' "$HDR/.config" | sort) <(grep '^CONFIG_' .config | sort) |
  grep '^[<>]' | grep -v -E 'CONFIG_(CC|GCC|CLANG|LD|AS|RUSTC|BINDGEN|PAHOLE|TOOLS|LLD|OBJTOOL)_|_VERSION(_TEXT)?=' || true)
if [[ -n $drift ]]; then
  say "note: $(wc -l <<<"$drift") kernel options resolve differently here than in $KREL's own build:"
  head -n 8 <<<"$drift" | sed 's/^/      /'
fi

for entry in "${PATCHES[@]}"; do
  read -r name _ <<<"$entry"
  p=../patches-src/patches/$name
  port=$OWN_PATCHES/$FLAVOUR/$name
  # Already part of this kernel version (a backported fix): skip.
  if patch -p1 -R --dry-run --force --fuzz=0 < "$p" >/dev/null 2>&1; then
    say "$name: already in $KVER"
    continue
  fi
  # No fuzz: a hunk that no longer matches exactly must stop the build.
  if patch -p1 --dry-run --force --fuzz=0 < "$p" >/dev/null 2>&1; then
    say "applying $name"
  elif [[ -n $OWN_PATCHES && -e $port ]] && patch -p1 --dry-run --force --fuzz=0 < "$port" >/dev/null 2>&1; then
    say "applying $name (as re-diffed for $FLAVOUR, patches/amdgpu/$FLAVOUR)"
    p=$port
  else
    die "$name does not apply cleanly to $PKGBASE $KVER: it needs porting to this kernel first"
  fi
  patch -p1 --fuzz=0 --quiet < "$p"
done

if [[ -n $OWN_PATCHES ]]; then
  for p in "$OWN_PATCHES"/*.patch; do
    [[ -e $p ]] || continue
    patch -p1 --dry-run --force --fuzz=0 < "$p" >/dev/null || die "${p##*/} does not apply cleanly"
    say "applying ${p##*/} (ours)"
    patch -p1 --fuzz=0 --quiet < "$p"
  done
fi

# Once more after the patches (kernel-source.sh did it before them): the
# module is only safe if every header it compiles against is the one the
# kernel was built with.
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
