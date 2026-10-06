// Guards the theme system: UI code must read colours from the active
// theme (context.palette), never from the Wreck palette directly, or it
// will not follow the user's theme choice.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files allowed to name AppColors.wreck: the theme layer itself.
bool _allowed(String path) => path.startsWith('lib/ui/theme/');

void main() {
  test('no UI code reads AppColors.wreck directly', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (_allowed(path)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // A painter has no BuildContext, so it may default to Wreck on a line
        // marked `// palette-fallback`.
        if (lines[i].contains('AppColors.wreck') &&
            !lines[i].contains('// palette-fallback')) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use context.palette instead:\n${offenders.join('\n')}');
  });
}
