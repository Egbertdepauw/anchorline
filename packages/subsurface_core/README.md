# subsurface_core

Holds the Subsurface format code (parser, serializer, mappers, sync planner) shared by the Anchorline app and the Anchorline server.
`lib/` may import no Flutter, Drift, PowerSync or I/O; `test/purity_test.dart` enforces it, and `column_packer.dart`'s `dart:io` zlib import is the one allowed exception.
The layout mirrors the app's `lib/` on purpose, so files keep the same relative paths when they move here.
Run the tests with `dart test` from this directory.
