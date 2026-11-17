import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('lib/ imports no Flutter, BLE, database or dart:io '
      '(except lib/src/hook/)', () {
    final forbidden = RegExp(
      r'''^\s*(import|export)\s+['"](dart:io|package:flutter[^'"]*|'''
      r'''package:flutter_blue_plus[^'"]*|package:drift[^'"]*|'''
      r'''package:powersync[^'"]*|package:sqlite3[^'"]*)['"]''',
      multiLine: true,
    );
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/src/hook/')) continue;
      final match = forbidden.firstMatch(entity.readAsStringSync());
      if (match != null) offenders.add('$path: ${match.group(0)!.trim()}');
    }
    expect(offenders, isEmpty);
  });
}
