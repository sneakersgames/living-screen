#!/usr/bin/env bash
# Builds the live/installer ISO in an Arch Linux container.
#   ./build.sh            -> out/odimac-<date>-x86_64.iso
# Needs docker (or podman via DOCKER=podman) and an x86_64 host.
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
[[ $(uname -m) == x86_64 ]] || { echo "build.sh: needs an x86_64 host" >&2; exit 1; }
mkdir -p out
# shellcheck disable=SC2086
exec "$docker" run --rm --privileged \
  -v "$PWD":/src:ro -v "$PWD/out":/out \
  -e OPENDISPLAY_REPO -e OPENDISPLAY_REF -e RECEIVER_CHECK -e KERNEL_PKGVER \
  -e HTTPS_PROXY -e HTTP_PROXY -e NO_PROXY -e https_proxy -e http_proxy -e no_proxy \
  ${DOCKER_ARGS:-} \
  "${BUILD_IMAGE:-archlinux:latest}" /src/scripts/build-inner.sh
