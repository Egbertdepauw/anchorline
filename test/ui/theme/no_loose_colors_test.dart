// Guards the theme system: colours in UI code come from the active theme
// (context.palette) or from the fixed classes in lib/ui/theme/
// (SafetyColors, DataColors, MediaColors). A colour literal or a named
// Material colour anywhere else will not follow the user's theme.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

bool _allowed(String path) => path.startsWith('lib/ui/theme/');

final _literal = RegExp(r'\bColor\(0x|\bColor\.from(ARGB|RGBO)?\(|'
    r'\bHSLColor\b|\bHSVColor\b|\bCupertinoColors\.');
final _named = RegExp(r'\bColors\.([a-zA-Z0-9]+)');

/// [line] without a trailing `//` comment. A `//` inside a single- or
/// double-quoted string (a URL, say) does not start a comment.
String _stripComment(String line) {
  String? quote;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quote != null) {
      if (c == r'\') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
    } else if (c == "'" || c == '"') {
      quote = c;
    } else if (c == '/' && i + 1 < line.length && line[i + 1] == '/') {
      return line.substring(0, i);
    }
  }
  return line;
}

/// Whether [line] holds a colour literal or a named Material colour other
/// than `Colors.transparent`. Colour names inside string literals are
/// flagged too: the scanner stays simple on purpose.
bool isLooseColorLine(String line) {
  final code = _stripComment(line);
  if (_literal.hasMatch(code)) return true;
  return _named.allMatches(code).any((m) => m.group(1) != 'transparent');
}

void main() {
  test('no colour literals or named Material colours outside lib/ui/theme',
      () {
    final offenders = <String>[];
    var scanned = 0;
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (_allowed(path)) continue;
      scanned++;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (isLooseColorLine(lines[i])) {
          offenders.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(scanned, greaterThan(100), reason: 'scanned only $scanned files');
    expect(offenders, isEmpty,
        reason: 'Use context.palette, SafetyColors, DataColors or '
            'MediaColors instead:\n${offenders.join('\n')}');
  });

  test('isLooseColorLine flags colours and ignores comments and safe forms',
      () {
    for (final line in [
      'color: Color(0xFF112233),',
      'final c = Colors.red;',
      'm.Colors.white70',
      'Color.fromARGB(255, 1, 2, 3)',
      'Color.fromRGBO(1, 2, 3, 1)',
      'CupertinoColors.systemRed',
      "launch('https://example.com'); final c = Colors.red;",
    ]) {
      expect(isLooseColorLine(line), isTrue, reason: line);
    }
    for (final line in [
      'color: Colors.transparent,',
      '// was Colors.red before',
      'color: SafetyColors.danger,',
      'color: DataColors.mapPin,',
      'x = 1; // Color(0xFF000000)',
    ]) {
      expect(isLooseColorLine(line), isFalse, reason: line);
    }
  });
}
