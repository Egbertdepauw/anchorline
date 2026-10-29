/// Line parser for the Divesoft SOLO gas analyzer USB serial output.
///
/// Pure Dart: no Flutter, no I/O. Transports split the serial stream into
/// lines and feed each one to [parseSoloLine].
///
/// Documented SOLO O2 line (one per second, CRLF-terminated):
///
///     O2 21.1 % Ti 23.9 ~C 1004.1 hPa 2021/12/20 12:03:00
///
/// The trimix SOLO adds a helium field in front:
///
///     He 35.0 O2 20.9 % Ti 23.9 ~C 1004.1 hPa 2026/10/27 20:30:00
///
/// The older Divesoft He/O2 analyzer sends `He xxx.x O2 yyy.y` with no
/// temperature, pressure or timestamp. A field that failed to measure is
/// sent as asterisks (`***.*`) and parsed as [double.nan]. The `~C` after
/// the temperature is the degree-Celsius unit.
///
/// Fields are matched by key, never by column position, so field order
/// and extra whitespace do not matter.
library;

import 'analyzer_reading.dart';

final RegExp _trailingTerminators = RegExp(r'[\r\n]+$');
final RegExp _whitespace = RegExp(r'\s+');

/// A value token: digits, dot, minus sign, or asterisks (error marker).
final RegExp _valueToken = RegExp(r'^[-\d.*]+$');

/// Pressure value with the unit glued on, e.g. `1004.1hPa`.
final RegExp _gluedHpa = RegExp(r'^([-\d.*]+)hpa$', caseSensitive: false);

final RegExp _timestamp = RegExp(
  r'(\d{4})/(\d{1,2})/(\d{1,2})\s+(\d{1,2}):(\d{2}):(\d{2})',
);

/// Parses one analyzer output line.
///
/// Returns null for lines that carry no O2 field (banners, blank lines,
/// garbage). With no He field (O2-only SOLO), `he` is 0.
AnalyzerReading? parseSoloLine(String line) {
  final raw = line.replaceAll(_trailingTerminators, '');
  final tokens = raw
      .trim()
      .split(_whitespace)
      .where((t) => t.isNotEmpty)
      .toList();

  double? o2;
  double? he;
  double? tempC;
  double? baroHpa;

  for (var i = 0; i < tokens.length; i++) {
    final next = i + 1 < tokens.length ? tokens[i + 1] : null;
    switch (tokens[i].toLowerCase()) {
      case 'o2':
        o2 ??= _parseValue(next);
      case 'he':
        he ??= _parseValue(next);
      case 'ti':
        tempC ??= _parseValue(next);
      case 'hpa':
        if (i > 0) baroHpa ??= _parseValue(tokens[i - 1]);
      default:
        final glued = _gluedHpa.firstMatch(tokens[i]);
        if (glued != null) baroHpa ??= _parseValue(glued.group(1));
    }
  }

  if (o2 == null) return null;

  return AnalyzerReading(
    o2: o2,
    he: he ?? 0,
    tempC: tempC,
    baroHpa: baroHpa,
    deviceTime: _parseTimestamp(raw),
    raw: raw,
  );
}

/// Parses a value token. Asterisks anywhere mean a sensor error (NaN);
/// anything that is not a number is treated as absent (null).
double? _parseValue(String? token) {
  if (token == null || !_valueToken.hasMatch(token)) return null;
  if (token.contains('*')) return double.nan;
  return double.tryParse(token);
}

/// Parses `yyyy/MM/dd HH:mm:ss` into a local [DateTime]. Returns null when
/// absent or out of range (the DateTime constructor would otherwise
/// silently roll e.g. month 13 over into the next year).
DateTime? _parseTimestamp(String line) {
  final m = _timestamp.firstMatch(line);
  if (m == null) return null;
  final year = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final day = int.parse(m.group(3)!);
  final hour = int.parse(m.group(4)!);
  final minute = int.parse(m.group(5)!);
  final second = int.parse(m.group(6)!);
  if (month < 1 || month > 12) return null;
  final daysInMonth = DateTime.utc(year, month + 1, 0).day;
  if (day < 1 || day > daysInMonth) return null;
  if (hour > 23 || minute > 59 || second > 59) return null;
  return DateTime(year, month, day, hour, minute, second);
}
