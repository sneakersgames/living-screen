#!/usr/bin/env bash
# Builds the live/installer ISO in an Arch Linux container.
#   ./build.sh            -> out/odimac-<date>-x86_64.iso
# Needs Docker (or podman via DOCKER=podman). On an Apple silicon Mac the
# x86_64 container runs emulated: enable "Use Rosetta for x86_64/amd64
# emulation" in Docker Desktop's settings, and expect the first build to be
# slow. The receiver and the 5K driver are cached in out/cache, so later
# builds only repackage the image.
#
#   OPENDISPLAY_REPO   git URL of the OpenDisplay source (default: upstream)
#   OPENDISPLAY_REF    branch or tag to build the receiver from (default: v1.30.3)
#   KERNEL_PKGVER      pinned Arch kernel package (default: 7.2.11.arch1-1, with the
#                      5K panel driver); "current" for Arch's kernel and 4K
#   RECEIVER_CHECK=1   also run the receiver's test suite
#   BUILD_IMAGE        container image (default: archlinux:latest)
#   DOCKER_ARGS        extra arguments for `docker run`
set -euo pipefail
cd "$(dirname "$0")"
docker=${DOCKER:-docker}
mkdir -p out/cache/pacman
# shellcheck disable=SC2086
exec "$docker" run --rm --privileged --platform linux/amd64 \
  -v "$PWD":/src:ro -v "$PWD/out":/out \
  -v "$PWD/out/cache/pacman":/var/cache/pacman/pkg \
  -e OPENDISPLAY_REPO -e OPENDISPLAY_REF -e RECEIVER_CHECK -e KERNEL_PKGVER \
  -e HTTPS_PROXY -e HTTP_PROXY -e NO_PROXY -e https_proxy -e http_proxy -e no_proxy \
  ${DOCKER_ARGS:-} \
  "${BUILD_IMAGE:-archlinux:latest}" /src/scripts/build-inner.sh
