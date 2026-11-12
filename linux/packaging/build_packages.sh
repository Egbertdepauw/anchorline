#!/usr/bin/env bash
# Turns the AppDir that build_appimage.sh made into installable packages:
# a .deb, an .rpm and an Arch .pkg.tar.zst, all from nfpm.yaml.
#
#   linux/packaging/build_packages.sh --version 1.1.0 --build 47 \
#       --appdir <Anchorline.AppDir> --out <dir>
#
# build_appimage.sh calls this at the end, so a normal release build makes
# the AppImage and the three packages together.
set -euo pipefail

die() {
  echo "build_packages.sh: $*" >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version=""
build=""
appdir=""
out=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --build) build="${2:-}"; shift 2 ;;
    --appdir) appdir="${2:-}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--version must look like 1.2.3, got '$version'"
[[ "$build" =~ ^[0-9]+$ ]] || die "--build must be a number, got '$build'"
[[ -x "$appdir/usr/bin/anchorline" ]] || die "--appdir '$appdir' has no usr/bin/anchorline"
[[ -n "$out" ]] || die "--out is required"
command -v nfpm >/dev/null || die "nfpm not found; run install_build_deps.sh"
mkdir -p "$out"

appdir="$(cd "$appdir" && pwd)"

# nfpm doesn't expand variables in file paths, so fill in nfpm.yaml's
# ${...} placeholders here.
config="$(mktemp)"
trap 'rm -f "$config"' EXIT
sed -e "s|\${ANCHORLINE_VERSION}|$version|g" \
    -e "s|\${ANCHORLINE_BUILD}|$build|g" \
    -e "s|\${ANCHORLINE_BUNDLE}|$appdir/usr/bin|g" \
    -e "s|\${ANCHORLINE_PACKAGING}|$script_dir|g" \
    -e "s|\${ANCHORLINE_ICON}|$appdir/usr/share/icons/hicolor/512x512/apps/nl.despaankamer.ccrlogger.png|g" \
    "$script_dir/nfpm.yaml" > "$config"

# Fixed, readable file names for the download page.
declare -A names=(
  [deb]="Anchorline-$version-linux-x64.deb"
  [rpm]="Anchorline-$version-linux-x64.rpm"
  [archlinux]="Anchorline-$version-linux-x64.pkg.tar.zst"
)
for packager in deb rpm archlinux; do
  target="$out/${names[$packager]}"
  rm -f "$target"
  nfpm package --config "$config" --packager "$packager" --target "$target"
done

echo
echo "Packages in $out:"
( cd "$out" && sha256sum "${names[deb]}" "${names[rpm]}" "${names[archlinux]}" )
