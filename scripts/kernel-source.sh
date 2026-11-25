#!/usr/bin/env bash
# Leaves the source tree an installed kernel was built from in
# WORKDIR/base-KREL, for the two driver builds.
#
#   kernel-source.sh KREL WORKDIR
#     KREL  kernel release whose headers are installed, e.g. 7.2.15-5-omarchy
#
# linux-omarchy (Omarchy's kernel) is kernel.org plus a patch set of its own,
# and some of those patches change structures the graphics driver shares with
# the kernel. Its tree is therefore made the way the package's own build
# makes it: the PKGBUILD of that exact release, from
# https://github.com/omacom/omarchy-pkgs, run up to and including its
# prepare() step. Any other kernel (Arch's `linux`) is taken as kernel.org's
# tarball. Either way the tree's headers are then compared with the installed
# kernel's, and a difference stops the build.
#
# The way to find the PKGBUILD's revision is that of
# https://github.com/ahmadtv/omarchy-imac18-3 (scripts/patch-imac5k-amdgpu.sh).
set -euo pipefail
KREL=${1:?kernel release} WORK=${2:?work dir}
OMARCHY_PKGS_REPO=${OMARCHY_PKGS_REPO:-https://github.com/omacom/omarchy-pkgs}
die() { echo "kernel-source: $*" >&2; exit 1; }
say() { echo "==> $*"; }

KVER=${KREL%%-*}                 # 7.2.15
HDR=/usr/lib/modules/$KREL/build
[[ -e $HDR/Module.symvers ]] || die "headers for $KREL are not installed"
PKGBASE=$(cat "/usr/lib/modules/$KREL/pkgbase" 2>/dev/null || echo linux)

mkdir -p "$WORK"; cd "$WORK"
base=$WORK/base-$KREL
if [[ -e $base/.odimac-complete ]]; then
  say "kernel source for $KREL: already there"
  exit 0
fi
rm -rf "$base"

kernel_org_source() {
  local src=linux-$KVER
  if [[ ! -f $src.tar.xz ]]; then
    say "downloading kernel $KVER source"
    curl -fL --retry 3 -o "$src.tar.xz.part" "https://cdn.kernel.org/pub/linux/kernel/v${KVER%%.*}.x/$src.tar.xz"
    mv "$src.tar.xz.part" "$src.tar.xz"
  fi
  curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v${KVER%%.*}.x/sha256sums.asc" \
    | grep " $src.tar.xz\$" | sha256sum -c --quiet || die "$src.tar.xz does not match kernel.org's checksum"
  say "extracting"
  rm -rf "$src"
  tar -xf "$src.tar.xz"
  mv "$src" "$base"
  # The release string's suffix (-arch1-1) is the builder's to set.
  touch "$base/.odimac-plain"
}

omarchy_source() {
  (( EUID )) || die "makepkg does not run as root: run this as a regular user"
  local repo=$WORK/omarchy-pkgs pb=pkgbuilds/$PKGBASE/PKGBUILD rel built commit="" newest="" c ct ver pr
  rel=${KREL#"$KVER"-}; rel=${rel%%-*}                  # 7.2.15-5-omarchy -> 5
  if [[ -d $repo/.git ]]; then
    git -C "$repo" fetch --quiet origin || die "could not update $repo"
  else
    git clone --quiet --filter=blob:none --no-checkout "$OMARCHY_PKGS_REPO" "$repo" || die "could not clone $OMARCHY_PKGS_REPO"
  fi
  # Several revisions can carry the same pkgver and pkgrel: patches land
  # first and the release number is raised later. The installed package was
  # built from the newest of them that is not newer than its own build date.
  built=$(LC_ALL=C pacman -Qi "$PKGBASE" 2>/dev/null | sed -n 's/^Build Date *: //p')
  built=$(date -d "$built" +%s 2>/dev/null || echo 0)
  while read -r c ct; do
    ver=$(git -C "$repo" show "$c:$pb" | sed -n 's/^pkgver=//p')
    pr=$(git -C "$repo" show "$c:$pb" | sed -n 's/^pkgrel=//p')
    [[ $ver == "$KVER" && $pr == "$rel" ]] || { [[ -z $newest ]] && continue || break; }
    [[ -n $newest ]] || newest=$c
    if (( built == 0 || ct <= built )); then commit=$c; break; fi
  done < <(git -C "$repo" log --format='%H %ct' origin/HEAD -- "$pb")
  if [[ -z $commit && -n $newest ]]; then
    say "no revision of $PKGBASE $KVER-$rel is older than the installed package; taking the newest"
    commit=$newest
  fi
  [[ -n $commit ]] || die "$PKGBASE $KVER-$rel is not in $OMARCHY_PKGS_REPO: cannot reproduce the source of $KREL"
  say "$PKGBASE $KVER-$rel: kernel.org $KVER + omarchy-pkgs ${commit:0:12}"

  local recipe=$WORK/recipe-$KREL
  rm -rf "$recipe"; mkdir -p "$recipe" "$WORK/sources"
  git -C "$repo" archive "$commit" "pkgbuilds/$PKGBASE" | tar -x -C "$recipe" --strip-components=2
  say "downloading and patching, as the package's own build does (makepkg --nobuild)"
  # The checksums in the PKGBUILD are verified; the signatures need keys this
  # machine does not have.
  (cd "$recipe" && SRCDEST="$WORK/sources" BUILDDIR="$recipe/build" PKGDEST="$recipe" \
    makepkg --nobuild --nodeps --skippgpcheck --noconfirm >"$recipe/makepkg.log" 2>&1) ||
    { tail -n 25 "$recipe/makepkg.log" >&2; die "the $PKGBASE recipe did not get through prepare()"; }
  local tree="" v
  for v in "$recipe"/build/*/src/linux-*/version "$recipe"/src/linux-*/version; do
    [[ -e $v && $(<"$v") == "$KREL" ]] && tree=${v%/version}
  done
  [[ -n $tree ]] || die "the recipe made no tree for $KREL (it made: $(cat "$recipe"/build/*/src/linux-*/version "$recipe"/src/linux-*/version 2>/dev/null | tr '\n' ' '))"
  mv "$tree" "$base"
  rm -rf "$recipe"
}

case $PKGBASE in
  linux-omarchy*) omarchy_source ;;
  *) kernel_org_source ;;
esac

# The drivers are only safe if every header they compile against is the one
# the kernel was built with. A module from other headers loads, and then
# reads the kernel's structures at the wrong places.
say "comparing headers with the installed $KREL"
hdrdiff=$(for d in include arch/x86/include; do
  diff -rq --exclude=generated --exclude=config "$base/$d" "$HDR/$d"
done 2>&1 || true)
[[ -z $hdrdiff ]] || { echo "$hdrdiff" | head -n 12 >&2; die "the source's headers differ from the installed kernel's"; }
touch "$base/.odimac-complete"
say "kernel source for $KREL ($PKGBASE) is in $base"
