#!/usr/bin/env bash
# Builds the Linux x64 release AppImage in Docker, from any machine with
# Docker (an Apple Silicon Mac runs the linux/amd64 image under emulation).
#
#   linux/packaging/build_in_docker.sh --version 1.1.0 --build 44 [--date 2026-11-07]
#       [--ref <commit>] [--out <dir>]
#
# Builds the committed tree of --ref (default HEAD; uncommitted changes are
# not included) with the recipe in this folder. --out defaults to
# build/desktop-<version>+<build> in this checkout. The Flutter SDK lives
# in the image, the pub cache in the Docker volume anchorline-linux-pub-cache.
set -euo pipefail

usage() {
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(git -C "$script_dir" rev-parse --show-toplevel)"
ref="HEAD"
out=""
version=""
build=""
build_date="$(date -u +%F)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --build) build="${2:-}"; shift 2 ;;
    --date) build_date="${2:-}"; shift 2 ;;
    --ref) ref="${2:-}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "build_in_docker.sh: unknown argument '$1'" >&2; usage ;;
  esac
done
[[ -n "$version" && -n "$build" ]] || usage

commit="$(git -C "$repo" rev-parse --verify "$ref^{commit}")"
out="${out:-$repo/build/desktop-$version+$build}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
image="anchorline-linux-builder"

echo "Building $commit ($(git -C "$repo" log -1 --format=%s "$commit"))"
docker build --platform linux/amd64 -t "$image" "$script_dir"

# The source goes in as a tar of the commit, so the build never writes
# into this checkout (.dart_tool, build/, linux/flutter/ephemeral).
git -C "$repo" archive --format=tar "$commit" |
  docker run --rm -i --platform linux/amd64 \
    -v anchorline-linux-pub-cache:/root/.pub-cache \
    -v "$script_dir:/packaging:ro" \
    -v "$out:/out" \
    "$image" \
    bash -c 'mkdir -p /work/src && tar -x -C /work/src && exec /packaging/build_appimage.sh --src /work/src --out /out "$@"' \
    _ --version "$version" --build "$build" --date "$build_date"
