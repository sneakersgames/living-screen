#!/bin/bash
# Run on the iMac, in a terminal of its Omarchy desktop: builds the packages
# for this machine as it is now, installs them, and turns the features on.
#
#   ./install.sh                build, install, set up
#   ./install.sh --autologin    and log in without a password at power-on
#   ./install.sh --no-drivers   without the 5K and sound drivers
#   ./install.sh --packages DIR install packages built elsewhere (./build.sh)
#
# The first run takes a while: the receiver is compiled, and for the 5K
# driver the kernel's source is downloaded (about 8 GB of disk) and the
# graphics driver built, 20 to 40 minutes on this iMac. Later runs reuse what
# has not changed. Run it again after an Omarchy update that brought a new
# kernel, before restarting: the drivers are built for the new kernel.
set -euo pipefail
cd "$(dirname "$0")"
die() { echo "install: $*" >&2; exit 1; }

setup_args=() packages="" drivers=1
while (( $# )); do
  case $1 in
    --autologin) setup_args+=(--autologin) ;;
    --no-drivers) drivers=0 ;;
    --packages) packages=${2:?--packages needs a directory}; shift ;;
    *) sed -n '2,14s/^# \{0,1\}//p' "$0"; exit 2 ;;
  esac
  shift
done
(( EUID )) || die "run this as yourself, not as root (it asks for your password where it needs it)"
command -v pacman >/dev/null || die "this is not Omarchy (no pacman)"
[[ -d ${OMARCHY_PATH:-/usr/share/omarchy} ]] || die "this is not Omarchy. Install Omarchy on the iMac first: https://omarchy.org"
model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
[[ $model == iMac18,3 ]] || echo "Note: this is a \"$model\", not an iMac18,3. The two drivers are made for that model only."

if [[ -z $packages ]]; then
  packages=$PWD/out
  if (( drivers )); then
    [[ $model == iMac18,3 ]] || die "the drivers are for the iMac18,3 only: run with --no-drivers"
    sudo pacman -S --noconfirm --needed linux-omarchy-headers
    scripts/build-packages.sh "$packages"
  else
    KREL=none scripts/build-packages.sh "$packages"
  fi
fi
compgen -G "$packages/odimac-[0-9]*.pkg.tar.zst" >/dev/null || die "no packages in $packages"

echo "==> installing"
sudo pacman -U --noconfirm "$packages"/*.pkg.tar.zst
odimac-setup "${setup_args[@]}"

running=$(uname -r)
for d in /usr/lib/modules/*/updates/amdgpu.ko.zst; do
  [[ -e $d ]] || continue
  for_kernel=${d#/usr/lib/modules/}; for_kernel=${for_kernel%%/*}
  echo
  if [[ $for_kernel == "$running" ]]; then
    echo "Restart the iMac to start the 5K and sound drivers."
  else
    echo "The drivers are for kernel $for_kernel, the one Omarchy starts next (running now: $running)."
    echo "Restart the iMac to use it."
  fi
done
