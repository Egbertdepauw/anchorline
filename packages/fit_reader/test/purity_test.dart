import 'dart:io';

import 'package:test/test.dart';

/// Import lines that would tie the package to the app or to a platform.
final _forbidden = RegExp(
  r"""^\s*(import|export)\s+'(package:flutter|package:drift|package:powersync|package:path/|dart:io|dart:ui|dart:ffi)""",
);

void main() {
  test('lib/ has no Flutter, Drift, PowerSync, path or I/O imports', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      for (final line in f.readAsLinesSync()) {
        if (_forbidden.hasMatch(line)) {
          offenders.add('${f.path}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('the barrel exports every lib/src file', () {
    final barrel = File('lib/fit_reader.dart').readAsStringSync();
    final missing = Directory('lib/src')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.dart'))
        .where((n) => !barrel.contains("export 'src/$n';"))
        .toList();
    expect(missing, isEmpty);
  });
}
