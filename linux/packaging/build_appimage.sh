#!/usr/bin/env bash
# Builds the Linux x64 release AppImage of Anchorline.
#
#   linux/packaging/build_appimage.sh --version 1.1.0 --build 44 [--date 2026-11-07]
#       [--src <checkout>] [--out <dir>]
#
# Runs on Ubuntu 22.04 x64 with Flutter on PATH and install_build_deps.sh
# applied: inside the Docker image next to this file (build_in_docker.sh
# does that), or directly on a CI runner. --src defaults to the checkout
# this script is in, --out to <src>/build/desktop-<version>+<build>.
# Release channel only; see docs/LINUX_DISTRIBUTION.md.
set -euo pipefail

usage() {
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

die() {
  echo "build_appimage.sh: $*" >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version=""
build=""
build_date="$(date -u +%F)"
src="$(cd "$script_dir/../.." && pwd)"
out=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --build) build="${2:-}"; shift 2 ;;
    --date) build_date="${2:-}"; shift 2 ;;
    --src) src="${2:-}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "build_appimage.sh: unknown argument '$1'" >&2; usage ;;
  esac
done

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--version must look like 1.2.3, got '$version'"
[[ "$build" =~ ^[0-9]+$ ]] || die "--build must be a number, got '$build'"
[[ "$build_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "--date must be yyyy-MM-dd, got '$build_date'"
[[ -f "$src/pubspec.yaml" ]] || die "--src '$src' is not the app checkout"
src="$(cd "$src" && pwd)"
out="${out:-$src/build/desktop-$version+$build}"

# This recipe only builds the release identity. A nightly needs
# ANCHORLINE_CHANNEL=nightly, BUILD_CHANNEL=nightly and its own desktop id
# and file name, none of which are wired up here yet.
case "${ANCHORLINE_CHANNEL:-}" in
  ""|release) ;;
  *) die "release builds only; unset ANCHORLINE_CHANNEL (got '$ANCHORLINE_CHANNEL')" ;;
esac
export ANCHORLINE_CHANNEL=release

[[ "$(uname -m)" == "x86_64" ]] || die "must run on x86_64, this is $(uname -m)"
command -v flutter >/dev/null || die "flutter is not on PATH"
appimagetool="${APPIMAGETOOL:-appimagetool}"
runtime="${APPIMAGE_RUNTIME:-/opt/appimagetool/runtime-x86_64}"
command -v "$appimagetool" >/dev/null || die "appimagetool not found; run install_build_deps.sh"
[[ -f "$runtime" ]] || die "AppImage runtime '$runtime' not found; run install_build_deps.sh"
command -v convert >/dev/null || die "ImageMagick (convert) not found; run install_build_deps.sh"
command -v patchelf >/dev/null || die "patchelf not found; run install_build_deps.sh"
# CMake's FindJNI (for package:jni) doesn't find Ubuntu's OpenJDK 21 on its
# own; a JAVA_HOME from the environment (setup-java) wins.
if [[ -z "${JAVA_HOME:-}" && -d /usr/lib/jvm/java-21-openjdk-amd64 ]]; then
  export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
fi
[[ -n "${JAVA_HOME:-}" ]] || die "no JDK: set JAVA_HOME or run install_build_deps.sh"
# No FUSE in containers or on CI runners. Only matters if APPIMAGETOOL
# points at an AppImage file rather than the unpacked tool.
export APPIMAGE_EXTRACT_AND_RUN=1

app_id="nl.despaankamer.ccrlogger"
appimage_name="Anchorline-$version-linux-x64.AppImage"

cd "$src"
flutter --version
flutter pub get --enforce-lockfile

# The five release defines, one argument each.
flutter build linux --release \
  --build-name="$version" \
  --build-number="$build" \
  --dart-define=BUILD_CHANNEL=release \
  --dart-define=DISTRIBUTION_CHANNEL=website \
  --dart-define=APP_VERSION="$version" \
  --dart-define=APP_BUILD="$build" \
  --dart-define=APP_BUILD_DATE="$build_date"

bundle="$src/build/linux/x64/release/bundle"
[[ -x "$bundle/anchorline" ]] || die "no anchorline executable in $bundle"
# Cheap proof that the defines reached the snapshot as separate values.
grep -q -a -F -- "$build_date" "$bundle/lib/libapp.so" \
  || die "APP_BUILD_DATE $build_date is not in libapp.so"
if grep -q -a -F -- 'release --dart-define' "$bundle/lib/libapp.so"; then
  die "libapp.so contains 'release --dart-define': the defines were glued together"
fi

# AppDir: the Flutter bundle in usr/bin, desktop entry and icon at the
# root (where appimagetool and desktop integration tools look) and in
# usr/share.
appdir="$src/build/linux-appimage/Anchorline.AppDir"
rm -rf "$appdir"
mkdir -p "$appdir/usr/bin" \
  "$appdir/usr/share/applications" \
  "$appdir/usr/share/icons/hicolor/512x512/apps"
cp -a "$bundle/." "$appdir/usr/bin/"

# package:jni comes in through sentry_flutter, which only uses it on
# Android; on Linux, Sentry goes through sentry-native and nothing opens
# libdartjni.so. The library links libjvm.so from the build machine's JDK,
# which a user's machine doesn't have, so it is left out.
rm -f "$appdir/usr/bin/lib/libdartjni.so"

# git2dart_binaries bundles libgit2.so (Subsurface sync) but not the
# libssh2.so.1 it links, and Ubuntu desktops don't install libssh2. Ship the
# package's own libssh2.so under its soname and let libgit2.so look next to
# itself for it.
git2dart_linux="$src/linux/flutter/ephemeral/.plugin_symlinks/git2dart_binaries/linux"
[[ -f "$git2dart_linux/libssh2.so" ]] || die "libssh2.so not found in $git2dart_linux"
install -m 0755 "$git2dart_linux/libssh2.so" "$appdir/usr/bin/lib/libssh2.so.1"
patchelf --set-rpath '$ORIGIN' "$appdir/usr/bin/lib/libgit2.so"

# Flutter copies the plugin libraries out of the build tree with their
# build-time RUNPATH (this machine's linux/flutter/ephemeral). Point them at
# their own folder, where libflutter_linux_gtk.so is. crashpad_handler
# (Sentry) comes with a RUNPATH of empty entries, which means "the current
# directory"; it only needs system libraries, so drop it.
for lib in "$appdir"/usr/bin/lib/lib*_plugin.so; do
  patchelf --set-rpath '$ORIGIN' "$lib"
done
find "$appdir/usr/bin" -name crashpad_handler -type f -exec patchelf --remove-rpath {} \;

install -m 0755 "$script_dir/AppRun" "$appdir/AppRun"
install -m 0644 "$script_dir/$app_id.desktop" "$appdir/$app_id.desktop"
install -m 0644 "$script_dir/$app_id.desktop" "$appdir/usr/share/applications/$app_id.desktop"
convert "$src/assets/brand/launcher-1024.png" -resize 512x512 \
  "$appdir/usr/share/icons/hicolor/512x512/apps/$app_id.png"
cp "$appdir/usr/share/icons/hicolor/512x512/apps/$app_id.png" "$appdir/$app_id.png"
ln -s "$app_id.png" "$appdir/.DirIcon"

mkdir -p "$out"
rm -f "$out/$appimage_name"
# --no-appstream: there is no AppStream metainfo file yet.
ARCH=x86_64 "$appimagetool" --no-appstream --runtime-file "$runtime" \
  "$appdir" "$out/$appimage_name"

echo
echo "AppImage: $out/$appimage_name"
( cd "$out" && sha256sum "$appimage_name" )
