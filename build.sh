#!/usr/bin/env bash
# Builds the packages in a container, for an iMac that runs Omarchy.
#   ./build.sh            -> out/*.pkg.tar.zst
# On the iMac itself, ./install.sh builds and installs in one go, without
# Docker.
#
# Needs Docker (or podman via DOCKER=podman). On an Apple silicon Mac the
# x86_64 container runs emulated: enable "Use Rosetta for x86_64/amd64
# emulation" in Docker Desktop's settings, and expect the first build to be
# slow. The receiver and the two drivers are cached in out/cache, so later
# builds only repackage.
#
#   OMARCHY_CHANNEL    stable (default), rc or edge: the channel the iMac's
#                      Omarchy follows. The drivers are built for that
#                      channel's current kernel.
#   KREL=none          leave the two drivers out
#   OPENDISPLAY_REPO   git URL of the OpenDisplay source (default: upstream)
#   OPENDISPLAY_REF    branch or tag to build the receiver from (default: v1.30.3)
#   OPENDISPLAY_PATCHES=0  build the receiver without patches/opendisplay
#   RECEIVER_CHECK=1   also run the receiver's test suite
#   BUILD_IMAGE        container image (default: archlinux:latest)
#   DOCKER_ARGS        extra arguments for `docker run`
set -euo pipefail
cd "$(dirname "$0")"
docker=${DOCKER:-docker}
mkdir -p out/cache/pacman
# shellcheck disable=SC2086
exec "$docker" run --rm --platform linux/amd64 \
  -v "$PWD":/src:ro -v "$PWD/out":/out \
  -v "$PWD/out/cache/pacman":/var/cache/pacman/pkg \
  -e OMARCHY_CHANNEL -e KREL \
  -e OPENDISPLAY_REPO -e OPENDISPLAY_REF -e OPENDISPLAY_PATCHES -e RECEIVER_CHECK \
  -e HTTPS_PROXY -e HTTP_PROXY -e NO_PROXY -e https_proxy -e http_proxy -e no_proxy \
  ${DOCKER_ARGS:-} \
  "${BUILD_IMAGE:-archlinux:latest}" /src/scripts/build-inner.sh
