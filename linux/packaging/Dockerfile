# Linux x64 build image for the Anchorline AppImage. Ubuntu 22.04 is the
# oldest LTS we build on, so the AppImage runs on distributions with
# glibc 2.35 or newer (Subsurface sync needs more; see
# docs/LINUX_DISTRIBUTION.md). Build it with --platform linux/amd64 (on an Apple
# Silicon Mac, Docker then runs it under emulation).
#
# Normally built and run by build_in_docker.sh; see docs/LINUX_DISTRIBUTION.md.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

COPY install_build_deps.sh /tmp/install_build_deps.sh
RUN /tmp/install_build_deps.sh && rm /tmp/install_build_deps.sh

# Flutter, pinned to one exact stable release. Bump it in lockstep with
# .github/workflows/check.yml.
ARG FLUTTER_VERSION=3.44.0
ARG FLUTTER_REVISION=559ffa3f75e7402d65a8def9c28389a9b2e6fe42
ARG FLUTTER_SHA256=e1ec95e6c550458a34de93580cb85dac24da0e9bedb9bb42811f050ac5a0c7d5
RUN curl -fsSL -o /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
 && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
 && tar -xJf /tmp/flutter.tar.xz -C /opt \
 && rm /tmp/flutter.tar.xz \
 && git config --system --add safe.directory /opt/flutter \
 && test "$(git -C /opt/flutter rev-parse HEAD)" = "${FLUTTER_REVISION}"

ENV PATH=/opt/flutter/bin:$PATH \
    PUB_CACHE=/root/.pub-cache

RUN flutter config --no-analytics --no-cli-animations \
 && dart --disable-analytics \
 && flutter precache --linux --no-android --no-ios --no-web --no-macos --no-windows --no-fuchsia \
 && flutter --version

WORKDIR /work
