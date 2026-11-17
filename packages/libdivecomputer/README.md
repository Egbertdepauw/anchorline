# libdivecomputer

Anchorline's wrapper around [libdivecomputer](https://www.libdivecomputer.org/),
the C library that talks to dive computers from many manufacturers. Phase 2 of
the libdivecomputer work uses it for Bluetooth computers other than
Shearwater. Shearwater keeps its pure-Dart reader.

This package vendors the upstream source under `third_party/libdivecomputer/`.
A native assets build hook compiles it, and `dart:ffi` bindings are generated
from its headers. Anchorline's own C layer is licensed LGPL-2.1-or-later, like
upstream.

## The pin

`UPSTREAM` names the upstream commit the tree comes from, and lists every local
patch. The vendored tree always equals "pinned commit + `patches/`", and the
pin moves only through the script:

```sh
tool/update_upstream.sh <40-hex commit>
```

It fetches upstream into a temporary directory, replaces `third_party/`,
applies the patches, regenerates `native/include/libdivecomputer/version.h`,
`native/revision.h` and `lib/src/upstream.g.dart`, runs ffigen when
`ffigen.yaml` exists, and rewrites `UPSTREAM`. `tool/check_vendor.sh` repeats
the update into a temporary copy and fails if the committed `third_party/`
differs; CI runs it.

## Patches

Every patch goes upstream first, to Jef Driesen, and there is no private fork.
A patch lives in `patches/` until upstream merges it, then the PR that moves
the pin deletes it. See `patches/README.md`.

## Moving the pin

A pin move is its own PR. It bumps `kLibdcParserVersion`, keeps every replay
test passing, and its description has a "Known changes" part that lists the
upstream commits between the two pins that touch a checked family.

## Tests

```sh
dart analyze --fatal-infos && dart test
```
