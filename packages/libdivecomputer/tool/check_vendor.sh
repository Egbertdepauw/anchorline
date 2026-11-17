#!/usr/bin/env bash
# Repeats the vendoring into a temporary copy of the package at the commit in
# UPSTREAM and fails if third_party/ differs from what is committed.
set -euo pipefail
export LC_ALL=C

root="$(cd "$(dirname "$0")/.." && pwd)"
commit="$(awk '$1 == "commit" { print $2 }' "$root/UPSTREAM")"
if [ -z "$commit" ]; then
  echo "no commit line in UPSTREAM" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/pkg"
cp -R "$root/UPSTREAM" "$root/patches" "$root/tool" "$tmp/pkg/"
mkdir -p "$tmp/pkg/third_party"

SKIP_FFIGEN=1 "$tmp/pkg/tool/update_upstream.sh" "$commit" > "$tmp/log" 2>&1 || {
  cat "$tmp/log" >&2
  exit 1
}

if ! diff -r "$root/third_party" "$tmp/pkg/third_party"; then
  echo "third_party/ is not 'pinned commit + patches/'. Run tool/update_upstream.sh $commit" >&2
  exit 1
fi
echo "third_party/ matches $commit"
