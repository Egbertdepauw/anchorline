import 'dart:io';

import 'package:test/test.dart';

/// Import lines that would tie the package to the app or to a platform.
/// `package:path` is listed because the only user was the snapshot's
/// directory walk, which belongs in the app.
final _forbidden = RegExp(
  r"""^\s*(import|export)\s+'(package:flutter|package:drift|package:powersync|package:path/|dart:io|dart:ui|dart:ffi)""",
);

/// `ZLibEncoder`/`ZLibDecoder` live in dart:io and have no pure-Dart
/// equivalent in the SDK. The column packer is the only file allowed to
/// import dart:io, and only for that.
const _allowed = {
  'lib/data/sample_codec/column_packer.dart': "import 'dart:io';",
};

void main() {
  test('lib/ has no Flutter, Drift, PowerSync, path or I/O imports', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      for (final line in f.readAsLinesSync()) {
        if (!_forbidden.hasMatch(line)) continue;
        if (_allowed[f.path] == line.trim()) continue;
        offenders.add('${f.path}: ${line.trim()}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('every lib/ file is exported by the barrel', () {
    final barrel = File('lib/subsurface_core.dart').readAsStringSync();
    final missing = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.substring('lib/'.length))
        .where((p) => p.endsWith('.dart') && p != 'subsurface_core.dart')
        .where((p) => !barrel.contains("export '$p';"))
        .toList();
    expect(missing, isEmpty);
  });
}
