// Guards the theme system: colours in UI code come from the active theme
// (context.palette) or from the fixed classes in lib/ui/theme/
// (SafetyColors, DataColors, MediaColors). A colour literal or a named
// Material colour anywhere else will not follow the user's theme.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

bool _allowed(String path) => path.startsWith('lib/ui/theme/');

final _literal = RegExp(
    r'\bColor\(0x|\bColor\.from(ARGB|RGBO)\(|\bHSLColor\b|\bHSVColor\b');
final _named = RegExp(r'\bColors\.([a-zA-Z0-9]+)');

void main() {
  test('no colour literals or named Material colours outside lib/ui/theme',
      () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (_allowed(path)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final code =
            line.contains('//') ? line.substring(0, line.indexOf('//')) : line;
        final named = _named
            .allMatches(code)
            .where((m) => m.group(1) != 'transparent')
            .isNotEmpty;
        if (_literal.hasMatch(code) || named) {
          offenders.add('$path:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use context.palette, SafetyColors, DataColors or '
            'MediaColors instead:\n${offenders.join('\n')}');
  });
}
