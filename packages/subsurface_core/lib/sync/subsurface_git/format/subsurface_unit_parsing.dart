// Helpers for parsing and serializing the small numeric / time / quoted-string
// lexemes that make up Subsurface's plain-text format.
//
// Round-trip safety is the load-bearing property here: we keep numeric values
// as their original lexeme strings everywhere we can, because re-serializing
// `double.parse(x).toString()` for `1.6m` produces `1.6000000000000001m` and
// breaks byte equivalence. Consumers that need the actual numeric value can
// call the lazy parsers below.

/// Quote and escape a string the way Subsurface does.
///
/// Subsurface escapes embedded `"` as `\"` and `\` as `\\`. Newlines and
/// tabs inside a quoted value are emitted *raw* (not as `\n` / `\t` escapes)
/// — which is why some Subsurface "lines" span multiple physical lines.
String quoteString(String value) {
  final buf = StringBuffer('"');
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    if (c == 0x22) {
      buf.write(r'\"');
    } else if (c == 0x5C) {
      buf.write(r'\\');
    } else {
      buf.writeCharCode(c);
    }
  }
  buf.write('"');
  return buf.toString();
}

/// Parse a `"..."` quoted string starting at [start] in [source]. The
/// returned [QuotedScan.endIndex] is the index immediately after the closing
/// quote.
///
/// Subsurface's quoting only escapes `"` and `\`. Any other backslash is
/// treated as a literal `\` followed by the next character.
QuotedScan scanQuotedString(String source, int start) {
  if (start >= source.length || source.codeUnitAt(start) != 0x22) {
    throw FormatException(
      'Expected `"` at offset $start in $source',
    );
  }
  final buf = StringBuffer();
  var i = start + 1;
  while (i < source.length) {
    final c = source.codeUnitAt(i);
    if (c == 0x5C && i + 1 < source.length) {
      final next = source.codeUnitAt(i + 1);
      if (next == 0x22) {
        buf.write('"');
        i += 2;
        continue;
      } else if (next == 0x5C) {
        buf.write(r'\');
        i += 2;
        continue;
      }
      // Unknown escape: keep the backslash verbatim and advance one char,
      // letting the next iteration handle the following character normally.
      buf.write(r'\');
      i += 1;
      continue;
    }
    if (c == 0x22) {
      return QuotedScan(value: buf.toString(), endIndex: i + 1);
    }
    buf.writeCharCode(c);
    i++;
  }
  throw FormatException(
    'Unterminated quoted string starting at offset $start',
  );
}

class QuotedScan {
  QuotedScan({required this.value, required this.endIndex});
  final String value;
  final int endIndex;
}

/// Parse a length lexeme like `1.6m`, `12.522m`, or `1.662m` into meters.
double? parseLengthMeters(String lexeme) {
  if (lexeme.endsWith('m')) {
    final n = double.tryParse(lexeme.substring(0, lexeme.length - 1));
    return n;
  }
  return null;
}

/// Parse a temperature lexeme like `11.0°C` into Celsius.
double? parseTempCelsius(String lexeme) {
  // The degree-C suffix is two code units in UTF-16: `°` (0x00B0) + `C`.
  if (lexeme.endsWith('°C')) {
    final n = double.tryParse(lexeme.substring(0, lexeme.length - 2));
    return n;
  }
  return null;
}

/// Parse a pressure lexeme like `207.946bar` (with no tank index) or
/// `207.946bar:0` (tank index 0). Returns the bar value and tank index (or
/// null if the lexeme had no `:N` suffix).
PressureLexeme? parsePressureBar(String lexeme) {
  // Find `bar` substring; everything before is the number, everything after
  // (optional `:N`) is the tank index.
  final barIdx = lexeme.indexOf('bar');
  if (barIdx <= 0) return null;
  final numStr = lexeme.substring(0, barIdx);
  final n = double.tryParse(numStr);
  if (n == null) return null;
  final tail = lexeme.substring(barIdx + 3);
  int? tankIndex;
  if (tail.isNotEmpty) {
    if (tail.startsWith(':')) {
      tankIndex = int.tryParse(tail.substring(1));
      if (tankIndex == null) return null;
    } else {
      return null;
    }
  }
  return PressureLexeme(bar: n, tankIndex: tankIndex);
}

class PressureLexeme {
  PressureLexeme({required this.bar, this.tankIndex});
  final double bar;
  final int? tankIndex;
}

/// Parse a time lexeme of the form `M:SS`, `MM:SS` or `HHH:SS` (or even
/// `H:MM:SS` for keyvalue stack times) into total seconds.
int? parseTimeSeconds(String lexeme) {
  final parts = lexeme.split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  try {
    if (parts.length == 2) {
      final m = int.parse(parts[0]);
      final s = int.parse(parts[1]);
      return m * 60 + s;
    } else {
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final s = int.parse(parts[2]);
      return h * 3600 + m * 60 + s;
    }
  } on FormatException {
    return null;
  }
}

/// Pad a `MM:SS`-style time lexeme to width 6 with leading spaces, the way
/// Subsurface formats sample-line times. Examples:
/// - `0:05` -> `  0:05`
/// - `10:05` -> ` 10:05`
/// - `100:05` -> `100:05`
/// - `1000:05` -> `1000:05` (unpadded; we never truncate).
String padSampleTime(String time) {
  if (time.length >= 6) return time;
  return time.padLeft(6);
}
