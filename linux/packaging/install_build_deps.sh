#!/usr/bin/env bash
# Installs everything build_appimage.sh needs, except Flutter itself, on
# Ubuntu 22.04 x64: the Flutter Linux toolchain, the system libraries the
# plugins compile against, a JDK, and the pinned AppImage tools.
#
# Used by the Dockerfile next to this file. On a CI runner:
#   sudo linux/packaging/install_build_deps.sh
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "install_build_deps.sh: run as root (sudo)" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
# - curl, git, unzip, xz-utils, zip: the Flutter tool. git also fetches
#   sentry-native at configure time (sentry_flutter uses FetchContent).
# - clang, cmake, ninja-build, pkg-config, libgtk-3-dev, liblzma-dev,
#   libstdc++-12-dev: Flutter's Linux desktop toolchain.
# - libsecret-1-dev: flutter_secure_storage_linux.
# - libcurl4-openssl-dev, zlib1g-dev: sentry-native (curl transport).
# - openjdk-21-jdk: package:jni (pulled in by sentry_flutter) does
#   find_package(JNI). Not the -headless variant: CMake 3.22's FindJNI also
#   insists on libjawt.so. build_appimage.sh points JAVA_HOME at this JDK
#   unless JAVA_HOME is already set (setup-java on a runner).
# - imagemagick: scales the launcher icon for the AppImage.
# - patchelf: lets the bundled libgit2.so find the bundled libssh2.
# - desktop-file-utils, file: appimagetool validates the .desktop file.
apt-get install -y --no-install-recommends \
  ca-certificates curl git unzip xz-utils zip \
  clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev \
  libsecret-1-dev \
  libcurl4-openssl-dev zlib1g-dev \
  openjdk-21-jdk \
  imagemagick patchelf \
  desktop-file-utils file
rm -rf /var/lib/apt/lists/*

# AppImage tools, pinned to fixed releases and checked by sha256 (the
# upstream "continuous" tags move). appimagetool would otherwise download
# the newest runtime itself; build_appimage.sh passes this one with
# --runtime-file instead.
APPIMAGETOOL_VERSION=1.9.1
APPIMAGETOOL_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
RUNTIME_VERSION=20251108
RUNTIME_SHA256=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d
tools_dir=/opt/appimagetool

rm -rf "$tools_dir"
mkdir -p "$tools_dir"
cd "$tools_dir"
curl -fsSL -o appimagetool-x86_64.AppImage \
  "https://github.com/AppImage/appimagetool/releases/download/${APPIMAGETOOL_VERSION}/appimagetool-x86_64.AppImage"
curl -fsSL -o runtime-x86_64 \
  "https://github.com/AppImage/type2-runtime/releases/download/${RUNTIME_VERSION}/runtime-x86_64"
sha256sum -c - <<EOF
${APPIMAGETOOL_SHA256}  appimagetool-x86_64.AppImage
${RUNTIME_SHA256}  runtime-x86_64
EOF
# Containers and CI runners have no FUSE, so unpack appimagetool once
# instead of mounting it on every run. Bytes 8-10 of an AppImage's ELF
# header hold its magic ("AI\x02"); emulators' binfmt rules (Rosetta and
# QEMU in Docker on Apple Silicon) don't accept that and fail with "Exec
# format error", so clear them first. A real x64 kernel ignores them.
chmod +x appimagetool-x86_64.AppImage
printf '\x00\x00\x00' | dd of=appimagetool-x86_64.AppImage bs=1 seek=8 count=3 conv=notrunc status=none
./appimagetool-x86_64.AppImage --appimage-extract >/dev/null
rm appimagetool-x86_64.AppImage
ln -sf "$tools_dir/squashfs-root/AppRun" /usr/local/bin/appimagetool
echo "appimagetool ${APPIMAGETOOL_VERSION}, runtime ${RUNTIME_VERSION} installed in ${tools_dir}"

# nfpm builds the .deb, .rpm and Arch packages (build_packages.sh), pinned
# and checked by sha256 like the AppImage tools.
NFPM_VERSION=2.48.0
NFPM_SHA256=6d7f9a28b2f397934403950fcbba83f598b08d02edbe79a0815b3b4897341750
curl -fsSL -o /tmp/nfpm.tar.gz \
  "https://github.com/goreleaser/nfpm/releases/download/v${NFPM_VERSION}/nfpm_${NFPM_VERSION}_Linux_x86_64.tar.gz"
echo "${NFPM_SHA256}  /tmp/nfpm.tar.gz" | sha256sum -c -
tar -xzf /tmp/nfpm.tar.gz -C /usr/local/bin nfpm
rm /tmp/nfpm.tar.gz
echo "nfpm ${NFPM_VERSION} installed"
