// Pure-Dart domain model for Subsurface's git-repo plain-text format.
//
// Subsurface stores its dive log as a tree of plain-text files in a git
// repository. Top-level metadata lives in `00-Subsurface`, dive sites live
// under `01-Divesites/Site-<id>`, and each dive lives in
// `<YYYY>/<MM>/<DD>-<Day>-<HH>=<MM>=<SS>/` containing a `Dive-<n>` annotation
// file and one or more `Divecomputer` (or `Divecomputer-NNN`) files.
//
// The model below is deliberately conservative: every parsed line keeps its
// verbatim source string, and the serializer emits that source string when
// present. That way round-tripping is byte-for-byte exact even for line types
// our parser doesn't know structurally.
//
// Phase B+ (constructing new dives in CCRLog and pushing them to Subsurface)
// will fill in the typed fields and rely on the serializer's "fallback"
// rendering path to emit text from those fields.

import 'subsurface_unit_parsing.dart';

/// One file's worth of Subsurface text (any of: 00-Subsurface, Site-*,
/// Dive-*, Divecomputer*).
///
/// The line list is kept in original order. Round-tripping serializes each
/// line via [SsLine.render], which prefers the verbatim [SsLine.source] when
/// available.
class SubsurfaceFile {
  SubsurfaceFile({required this.lines});

  final List<SsLine> lines;
}

// --- Line hierarchy ---------------------------------------------------------

/// Base class for one line of a Subsurface text file.
///
/// Some lines (e.g. `notes "..."` with a multi-line quoted string) span
/// multiple physical newlines in the file; conceptually they're still one
/// "logical line" in the format and so live as a single [SsLine].
sealed class SsLine {
  SsLine({this.source});

  /// Verbatim source text for this logical line, if known. Does NOT include
  /// the terminating newline. May contain embedded `\n` bytes for multi-line
  /// quoted strings (e.g. `notes "foo\nbar"`).
  ///
  /// When non-null, the serializer must emit exactly this string. When null,
  /// the serializer falls back to rendering from structured fields.
  String? source;

  /// Render this line to text (without trailing newline). Default
  /// implementation returns [source] when present.
  String render() {
    final s = source;
    if (s != null) return s;
    return renderFromFields();
  }

  /// Subclasses with structured fields must implement this for the case where
  /// [source] is null (i.e. when constructing a new line from data). Lines
  /// that are pure containers for raw text can throw.
  String renderFromFields();
}

/// A line we didn't recognize structurally. Forward-compatibility safety net.
class RawLine extends SsLine {
  RawLine(String text) : super(source: text);

  @override
  String renderFromFields() {
    // A RawLine without source is meaningless; the constructor enforces
    // source. This branch should never run.
    throw StateError('RawLine has no source');
  }
}

/// `key value` line where the value is a single unquoted token (e.g.
/// `duration 56:20 min`, `rating 2`, `divesiteid 456b7d53`,
/// `maxdepth 18.0m`, `salinity 1000g/l`).
///
/// The value is stored as the verbatim portion after the first space, so
/// unit suffixes / multi-token tails (`52:20 min`, `1000g/l`) are preserved
/// without interpretation.
class ScalarLine extends SsLine {
  ScalarLine({required this.key, required this.value, super.source});

  final String key;
  final String value;

  @override
  String renderFromFields() => '$key $value';
}

/// A keyless single-token line (just `invalid`).
class FlagLine extends SsLine {
  FlagLine({required this.key, super.source});

  final String key;

  @override
  String renderFromFields() => key;
}

/// `key "quoted string"` line. The quoted value can span multiple physical
/// lines and contain backslash-escaped quotes.
class QuotedLine extends SsLine {
  QuotedLine({required this.key, required this.value, super.source});

  final String key;

  /// The unescaped value. `\"` in the source becomes `"` here, and `\\`
  /// becomes `\`. Other characters (including raw newlines and tabs) pass
  /// through.
  final String value;

  @override
  String renderFromFields() => '$key ${quoteString(value)}';
}

/// `tags "a", "b", "c"` line.
class TagsLine extends SsLine {
  TagsLine({required this.tags, super.source});

  final List<String> tags;

  @override
  String renderFromFields() =>
      'tags ${tags.map(quoteString).join(', ')}';
}

/// `gps <lat> <lon>` line in a Site file.
class GpsLine extends SsLine {
  GpsLine({required this.lat, required this.lon, super.source});

  /// Verbatim lexeme (preserves precision).
  final String lat;
  final String lon;

  @override
  String renderFromFields() => 'gps $lat $lon';
}

/// `geo cat <n> origin <n> "name"` line in a Site file.
class GeoLine extends SsLine {
  GeoLine({
    required this.cat,
    required this.origin,
    required this.name,
    super.source,
  });

  final String cat;
  final String origin;
  final String name;

  @override
  String renderFromFields() =>
      'geo cat $cat origin $origin ${quoteString(name)}';
}

/// `keyvalue "Key" "Value"` line in a Divecomputer file.
class KeyvaluePairLine extends SsLine {
  KeyvaluePairLine({
    required this.key,
    required this.value,
    super.source,
  });

  final String key;
  final String value;

  @override
  String renderFromFields() =>
      'keyvalue ${quoteString(key)} ${quoteString(value)}';
}

/// `tanksensormapping "<a>" "<b>"` line.
class TankSensorMappingLine extends SsLine {
  TankSensorMappingLine({
    required this.tankIndex,
    required this.sensorId,
    super.source,
  });

  final String tankIndex;
  final String sensorId;

  @override
  String renderFromFields() =>
      'tanksensormapping ${quoteString(tankIndex)} ${quoteString(sensorId)}';
}

/// `divecomputerid "model" deviceid=... serial="..." nickname="..."` line.
///
/// First positional value is a quoted model name; remaining tokens are
/// `key=value` (with the value either bare or quoted) in arbitrary order
/// preserved by the parser.
class DivecomputerIdLine extends SsLine {
  DivecomputerIdLine({
    required this.model,
    required this.fields,
    super.source,
  });

  /// Quoted positional value following `divecomputerid `.
  final String model;

  /// Key=value pairs in their original order. Values are stored as raw
  /// lexemes including any surrounding quotes — i.e. `serial="2.9.5"` is
  /// stored as `serial -> "2.9.5"` (with the quotes preserved).
  final List<MapEntry<String, String>> fields;

  @override
  String renderFromFields() {
    final buf = StringBuffer('divecomputerid ${quoteString(model)}');
    for (final e in fields) {
      buf.write(' ${e.key}=${e.value}');
    }
    return buf.toString();
  }
}

/// `fingerprint model=... serial=... deviceid=... diveid=... data="..."`.
class FingerprintLine extends SsLine {
  FingerprintLine({required this.fields, super.source});

  /// Key=value pairs in their original order, values stored as raw lexemes
  /// (with quotes preserved when present).
  final List<MapEntry<String, String>> fields;

  @override
  String renderFromFields() {
    final buf = StringBuffer('fingerprint');
    for (final e in fields) {
      buf.write(' ${e.key}=${e.value}');
    }
    return buf.toString();
  }
}

/// `cylinder vol=3.0l workpressure=232.0bar description="3ℓ 232 bar" o2=99.0% ...`
///
/// Subsurface emits cylinder fields in a fixed order, and reordering them
/// would break byte-equivalence. We keep them as an ordered list and let the
/// caller reason about which keys are present.
class CylinderLine extends SsLine {
  CylinderLine({required this.fields, super.source});

  /// Key=value pairs in their original (Subsurface canonical) order. Values
  /// are stored verbatim (with quotes when present).
  final List<MapEntry<String, String>> fields;

  String? get(String key) {
    for (final e in fields) {
      if (e.key == key) return e.value;
    }
    return null;
  }

  @override
  String renderFromFields() {
    final buf = StringBuffer('cylinder');
    for (final e in fields) {
      buf.write(' ${e.key}=${e.value}');
    }
    return buf.toString();
  }
}

/// `weightsystem weight=5.0kg description="unknown"` line.
class WeightsystemLine extends SsLine {
  WeightsystemLine({required this.fields, super.source});

  final List<MapEntry<String, String>> fields;

  @override
  String renderFromFields() {
    final buf = StringBuffer('weightsystem');
    for (final e in fields) {
      buf.write(' ${e.key}=${e.value}');
    }
    return buf.toString();
  }
}

/// `units PERSONALIZE METERS LITER BAR CELSIUS KG MINUTES` line.
class UnitsLine extends SsLine {
  UnitsLine({required this.tokens, super.source});

  final List<String> tokens;

  @override
  String renderFromFields() => 'units ${tokens.join(' ')}';
}

/// `prefs DCCEILING` etc. — single keyword preference flag.
class PrefsLine extends SsLine {
  PrefsLine({required this.tokens, super.source});

  final List<String> tokens;

  @override
  String renderFromFields() => 'prefs ${tokens.join(' ')}';
}

/// `event MM:SS type=N [flags=N | value=N] name="..." [cylinder=N o2=...% he=...%]`.
class EventLine extends SsLine {
  EventLine({
    required this.time,
    required this.fields,
    super.source,
  });

  /// Verbatim time lexeme, e.g. `0:05` or `48:49`.
  final String time;

  /// Key=value pairs in their original order. Values are stored verbatim,
  /// preserving any quotes (e.g. `name -> "gaschange"`).
  final List<MapEntry<String, String>> fields;

  @override
  String renderFromFields() {
    final buf = StringBuffer('event $time');
    for (final e in fields) {
      buf.write(' ${e.key}=${e.value}');
    }
    return buf.toString();
  }
}

/// One sample line in a Divecomputer file:
///
///     `  0:05 1.6m 11.0°C 207.946bar:0 sensor1=0.714bar po2=0.7bar`
///
/// The first field is the time (right-padded to width 6 in the original).
/// Optional positional fields follow: depth (always present in practice),
/// temperature, and one or more tank pressures (`X.Ybar:N` or `X.Ybar`).
/// Then a sequence of `key=value` tokens.
///
/// Each sample is "sparse": only changed fields are emitted vs. the previous
/// sample, so a token's absence means "unchanged from prior".
class SampleLine extends SsLine {
  SampleLine({
    required this.time,
    required this.positional,
    required this.kv,
    super.source,
  });

  /// Time lexeme like `0:05` (without leading padding).
  final String time;

  /// Verbatim positional tokens after the time, in order. Examples:
  /// `1.6m`, `11.0°C`, `207.946bar:0`, `139.964bar:1`, `187.951bar`.
  final List<String> positional;

  /// `key=value` pairs in original order. Values are verbatim lexemes such
  /// as `0.714bar`, `1:00`, `99:00`, `1%`, `1`.
  final List<MapEntry<String, String>> kv;

  @override
  String renderFromFields() {
    final padded = time.padLeft(6);
    final buf = StringBuffer(padded);
    for (final p in positional) {
      buf.write(' ');
      buf.write(p);
    }
    for (final e in kv) {
      buf.write(' ');
      buf.write(e.key);
      buf.write('=');
      buf.write(e.value);
    }
    return buf.toString();
  }
}

/// Convenience: a typed view of the depth positional token. The first
/// positional token, in practice, is always the depth (`X.Ym` or `X.Ymm`).
extension SampleLineDepth on SampleLine {
  /// Raw lexeme of the depth value, e.g. `1.6m`. Null if no positional
  /// tokens were present (we have not seen this in real data, but guard
  /// against it).
  String? get depthLexeme => positional.isEmpty ? null : positional.first;

  /// Parsed depth in meters as a [double], or null. Use sparingly — prefer
  /// [depthLexeme] for round-trip-safe storage.
  double? get depthMeters {
    final lex = depthLexeme;
    if (lex == null) return null;
    return parseLengthMeters(lex);
  }
}
