// Pure-Dart parser for Subsurface's plain-text git-repo format.
//
// The parser is intentionally lenient: any line type it doesn't recognise is
// preserved as a [RawLine] so future Subsurface additions don't break round-
// trip. Every parsed line keeps its verbatim source string, so round-tripping
// (parse -> serialize) is byte-for-byte exact regardless of how thoroughly we
// understand the line's structure.

import 'subsurface_format.dart';
import 'subsurface_unit_parsing.dart';

/// Which kind of file we're parsing. Different file kinds treat the same
/// keyword differently (e.g. `model` is plain in a Site or top-level file
/// but quoted-string-typed in a Divecomputer).
enum SubsurfaceFileKind {
  /// `00-Subsurface` top-level metadata file.
  top,

  /// `01-Divesites/Site-<id>` divesite file.
  site,

  /// `Dive-<n>` annotation file inside a dive folder.
  dive,

  /// `Divecomputer` or `Divecomputer-NNN` log file inside a dive folder.
  divecomputer,
}

/// Top-level entry point. Parses a full file's contents into a
/// [SubsurfaceFile] of typed (or [RawLine]-fallback) lines.
SubsurfaceFile parseSubsurfaceFile(
  String text, {
  required SubsurfaceFileKind kind,
}) {
  final scanner = _LineScanner(text);
  final lines = <SsLine>[];
  while (!scanner.atEnd) {
    final line = _parseLogicalLine(scanner, kind: kind);
    lines.add(line);
  }
  return SubsurfaceFile(lines: lines);
}

// --- Internals --------------------------------------------------------------

/// Reads the input as a sequence of logical lines. Most logical lines are
/// terminated by `\n`, but a quoted-string value can contain raw newlines, so
/// we sometimes consume past `\n` until the closing `"`.
class _LineScanner {
  _LineScanner(this.source);

  final String source;
  int offset = 0;

  bool get atEnd => offset >= source.length;

  /// Consumes from the current offset up to and including the next `\n`,
  /// returning the line content WITHOUT the trailing `\n`. If the input
  /// doesn't end in `\n`, returns the remaining text and advances to EOF.
  String readPhysicalLine() {
    final start = offset;
    var i = start;
    while (i < source.length && source.codeUnitAt(i) != 0x0A) {
      i++;
    }
    final content = source.substring(start, i);
    offset = i < source.length ? i + 1 : i;
    return content;
  }

  /// Reads from the current offset. If a quoted string begins on the line
  /// and isn't closed before the trailing `\n`, keep reading further
  /// physical lines until it closes. Returns the full logical line WITHOUT
  /// the terminating newline of its last physical line.
  String readLogicalLine() {
    final start = offset;

    // Walk forward looking for the end of the logical line. A logical line
    // ends at the first `\n` that is *not* inside an open quoted string.
    var i = start;
    var inString = false;
    while (i < source.length) {
      final c = source.codeUnitAt(i);
      if (inString) {
        if (c == 0x5C && i + 1 < source.length) {
          // Skip the next character — backslash escapes both `"` and `\`,
          // and unknown escapes keep the next character literal.
          i += 2;
          continue;
        }
        if (c == 0x22) {
          inString = false;
          i++;
          continue;
        }
        i++;
        continue;
      }
      if (c == 0x22) {
        inString = true;
        i++;
        continue;
      }
      if (c == 0x0A) {
        // End of logical line.
        final content = source.substring(start, i);
        offset = i + 1;
        return content;
      }
      i++;
    }
    // EOF without trailing newline.
    final content = source.substring(start, i);
    offset = i;
    return content;
  }
}

SsLine _parseLogicalLine(
  _LineScanner scanner, {
  required SubsurfaceFileKind kind,
}) {
  final line = scanner.readLogicalLine();

  // Sample lines start with one or more spaces followed by a digit.
  if (kind == SubsurfaceFileKind.divecomputer && _looksLikeSampleLine(line)) {
    return _parseSampleLine(line);
  }

  if (line.isEmpty) {
    return RawLine(line);
  }

  // Find the first space; everything before it is the bare keyword.
  final spaceIdx = line.indexOf(' ');
  final key = spaceIdx < 0 ? line : line.substring(0, spaceIdx);
  final rest = spaceIdx < 0 ? '' : line.substring(spaceIdx + 1);

  switch (key) {
    case 'tags':
      return _parseTags(rest, line);
    case 'gps':
      return _parseGps(rest, line);
    case 'geo':
      return _parseGeo(rest, line);
    case 'keyvalue':
      return _parseKeyvalue(rest, line);
    case 'tanksensormapping':
      return _parseTanksensormapping(rest, line);
    case 'divecomputerid':
      return _parseDivecomputerId(rest, line);
    case 'fingerprint':
      return _parseFingerprint(rest, line);
    case 'cylinder':
      return _parseFieldList(
        rest,
        line,
        builder: (fields) => CylinderLine(fields: fields, source: line),
      );
    case 'weightsystem':
      return _parseFieldList(
        rest,
        line,
        builder: (fields) => WeightsystemLine(fields: fields, source: line),
      );
    case 'event':
      return _parseEvent(rest, line);
    case 'units':
      return UnitsLine(tokens: rest.split(' '), source: line);
    case 'prefs':
      return PrefsLine(tokens: rest.split(' '), source: line);
    case 'invalid':
      // Standalone keyword line (no value).
      if (rest.isEmpty) return FlagLine(key: 'invalid', source: line);
      // Defensive fallback if a future Subsurface adds args.
      return ScalarLine(key: 'invalid', value: rest, source: line);
  }

  // Quoted-string-valued keys (file-kind dependent). These can span
  // multiple physical lines via raw newlines inside the quoted value.
  if (rest.isNotEmpty && rest.codeUnitAt(0) == 0x22) {
    final quoted = scanQuotedString(rest, 0);
    // Quoted values must consume the entire `rest`; otherwise this isn't a
    // simple `key "value"` line.
    if (quoted.endIndex == rest.length) {
      return QuotedLine(key: key, value: quoted.value, source: line);
    }
  }

  // Bare keyword + free-form value: use ScalarLine. This covers `duration
  // 56:20 min`, `rating 2`, `divesiteid 456b7d53`, `maxdepth 18.0m`,
  // `salinity 1000g/l`, `airtemp 25.0°C`, etc.
  if (rest.isEmpty) {
    return FlagLine(key: key, source: line);
  }
  return ScalarLine(key: key, value: rest, source: line);
}

bool _looksLikeSampleLine(String line) {
  if (line.isEmpty) return false;
  // Subsurface right-pads sample timestamps to 4 chars in the minute
  // field, which means the leading whitespace count varies by dive
  // duration:
  //   `  0:05`  (2-space pad — 1-digit minutes)
  //   ` 99:55`  (1-space pad — 2-digit minutes)
  //   `100:00`  (0-space pad — 3-digit minutes, dives >= 100 min)
  // So we don't require a leading space; we just look for a `MMM:SS`-shaped
  // time prefix. Top-level header lines (`model`, `keyvalue`, `event`, …)
  // start with a letter, so this still discriminates correctly.
  var i = 0;
  while (i < line.length && line.codeUnitAt(i) == 0x20) {
    i++;
  }
  if (i >= line.length) return false;
  final c = line.codeUnitAt(i);
  if (c < 0x30 || c > 0x39) return false;
  // Must have a `:` somewhere in the time before the next space.
  var j = i;
  while (j < line.length && line.codeUnitAt(j) != 0x20) {
    if (line.codeUnitAt(j) == 0x3A) return true;
    j++;
  }
  return false;
}

SampleLine _parseSampleLine(String line) {
  // Strip leading spaces and split into tokens. The first token is the time;
  // following tokens are positional (no `=`) until we hit a `key=value` token.
  var i = 0;
  while (i < line.length && line.codeUnitAt(i) == 0x20) {
    i++;
  }
  final stripped = line.substring(i);
  final tokens = stripped.split(' ').where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) {
    // Defensive: empty sample line; preserve verbatim.
    return SampleLine(
      time: '',
      positional: const [],
      kv: const [],
      source: line,
    );
  }
  final time = tokens.first;
  final rest = tokens.skip(1);
  final positional = <String>[];
  final kv = <MapEntry<String, String>>[];
  var sawKv = false;
  for (final tok in rest) {
    final eq = tok.indexOf('=');
    if (eq < 0) {
      if (sawKv) {
        // Tokens after we've seen a kv shouldn't be positional. Treat as kv
        // with empty value to be safe; this round-trips via the source.
        kv.add(MapEntry(tok, ''));
      } else {
        positional.add(tok);
      }
    } else {
      sawKv = true;
      kv.add(MapEntry(tok.substring(0, eq), tok.substring(eq + 1)));
    }
  }
  return SampleLine(
    time: time,
    positional: positional,
    kv: kv,
    source: line,
  );
}

TagsLine _parseTags(String rest, String source) {
  final tags = <String>[];
  var i = 0;
  while (i < rest.length) {
    while (i < rest.length &&
        (rest.codeUnitAt(i) == 0x20 || rest.codeUnitAt(i) == 0x2C)) {
      i++;
    }
    if (i >= rest.length) break;
    if (rest.codeUnitAt(i) != 0x22) {
      // Unknown shape; bail to RawLine semantics.
      return TagsLine(tags: tags, source: source);
    }
    final scan = scanQuotedString(rest, i);
    tags.add(scan.value);
    i = scan.endIndex;
  }
  return TagsLine(tags: tags, source: source);
}

GpsLine _parseGps(String rest, String source) {
  final parts = rest.split(' ');
  if (parts.length >= 2) {
    return GpsLine(lat: parts[0], lon: parts[1], source: source);
  }
  return GpsLine(lat: rest, lon: '', source: source);
}

SsLine _parseGeo(String rest, String source) {
  // `cat <n> origin <n> "Country"`
  final tokens = _tokenizeWithQuotes(rest);
  if (tokens.length >= 5 &&
      tokens[0] == 'cat' &&
      tokens[2] == 'origin' &&
      tokens[4].startsWith('"')) {
    final cat = tokens[1];
    final origin = tokens[3];
    final scan = scanQuotedString(tokens[4], 0);
    return GeoLine(
      cat: cat,
      origin: origin,
      name: scan.value,
      source: source,
    );
  }
  return RawLine(source);
}

SsLine _parseKeyvalue(String rest, String source) {
  if (rest.isEmpty || rest.codeUnitAt(0) != 0x22) return RawLine(source);
  final keyScan = scanQuotedString(rest, 0);
  var i = keyScan.endIndex;
  while (i < rest.length && rest.codeUnitAt(i) == 0x20) {
    i++;
  }
  if (i >= rest.length || rest.codeUnitAt(i) != 0x22) return RawLine(source);
  final valScan = scanQuotedString(rest, i);
  return KeyvaluePairLine(
    key: keyScan.value,
    value: valScan.value,
    source: source,
  );
}

SsLine _parseTanksensormapping(String rest, String source) {
  if (rest.isEmpty || rest.codeUnitAt(0) != 0x22) return RawLine(source);
  final aScan = scanQuotedString(rest, 0);
  var i = aScan.endIndex;
  while (i < rest.length && rest.codeUnitAt(i) == 0x20) {
    i++;
  }
  if (i >= rest.length || rest.codeUnitAt(i) != 0x22) return RawLine(source);
  final bScan = scanQuotedString(rest, i);
  return TankSensorMappingLine(
    tankIndex: aScan.value,
    sensorId: bScan.value,
    source: source,
  );
}

SsLine _parseDivecomputerId(String rest, String source) {
  if (rest.isEmpty || rest.codeUnitAt(0) != 0x22) return RawLine(source);
  final modelScan = scanQuotedString(rest, 0);
  final fields = _parseKeyValueFields(rest, modelScan.endIndex);
  return DivecomputerIdLine(
    model: modelScan.value,
    fields: fields,
    source: source,
  );
}

SsLine _parseFingerprint(String rest, String source) {
  final fields = _parseKeyValueFields(rest, 0);
  return FingerprintLine(fields: fields, source: source);
}

SsLine _parseFieldList(
  String rest,
  String source, {
  required SsLine Function(List<MapEntry<String, String>>) builder,
}) {
  final fields = _parseKeyValueFields(rest, 0);
  return builder(fields);
}

SsLine _parseEvent(String rest, String source) {
  // `MM:SS <key=value>...` — the time is the first space-delimited token.
  final firstSpace = rest.indexOf(' ');
  if (firstSpace < 0) return RawLine(source);
  final time = rest.substring(0, firstSpace);
  final fields = _parseKeyValueFields(rest, firstSpace + 1);
  return EventLine(time: time, fields: fields, source: source);
}

/// Parse a sequence of `key=value` tokens starting at [start] in [text].
/// Values may be quoted (`name="gas change"`), in which case the quoted
/// content (including embedded spaces) is the value. Bare values run up to
/// the next space.
///
/// The returned list preserves order. Each value is stored as the raw lexeme
/// — i.e. quoted values include their surrounding quotes.
List<MapEntry<String, String>> _parseKeyValueFields(String text, int start) {
  final out = <MapEntry<String, String>>[];
  var i = start;
  while (i < text.length) {
    while (i < text.length && text.codeUnitAt(i) == 0x20) {
      i++;
    }
    if (i >= text.length) break;
    // Read key up to `=`.
    final keyStart = i;
    while (i < text.length &&
        text.codeUnitAt(i) != 0x3D &&
        text.codeUnitAt(i) != 0x20) {
      i++;
    }
    final key = text.substring(keyStart, i);
    if (i >= text.length || text.codeUnitAt(i) != 0x3D) {
      // Token without `=` — record as bare key with empty value. Caller can
      // still serialize via `source`.
      out.add(MapEntry(key, ''));
      continue;
    }
    i++; // consume `=`
    // Read value: quoted or bare.
    if (i < text.length && text.codeUnitAt(i) == 0x22) {
      final scan = scanQuotedString(text, i);
      out.add(MapEntry(key, text.substring(i, scan.endIndex)));
      i = scan.endIndex;
    } else {
      final valStart = i;
      while (i < text.length && text.codeUnitAt(i) != 0x20) {
        i++;
      }
      out.add(MapEntry(key, text.substring(valStart, i)));
    }
  }
  return out;
}

/// Tokenize a string, treating quoted segments as a single token and
/// preserving the quotes in the output.
List<String> _tokenizeWithQuotes(String text) {
  final out = <String>[];
  var i = 0;
  while (i < text.length) {
    while (i < text.length && text.codeUnitAt(i) == 0x20) {
      i++;
    }
    if (i >= text.length) break;
    if (text.codeUnitAt(i) == 0x22) {
      final scan = scanQuotedString(text, i);
      out.add(text.substring(i, scan.endIndex));
      i = scan.endIndex;
    } else {
      final start = i;
      while (i < text.length && text.codeUnitAt(i) != 0x20) {
        i++;
      }
      out.add(text.substring(start, i));
    }
  }
  return out;
}
