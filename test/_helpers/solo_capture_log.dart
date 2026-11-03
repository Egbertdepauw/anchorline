/// Reads the SOLO captures written by `tool/solo_capture.py` and builds the
/// record the ESP32 bridge would have made from them (issue #113).
///
/// A capture line looks like
///
///     <seconds since start> <wall clock> RX <hex-escaped line>
///     <seconds since start> <wall clock> GAP <seconds>
///
/// A GAP line is printed when the silence ENDS, so it carries the time the
/// data resumed and how long it had lasted. In the SOLO's suspend (OK) the
/// held line is the last one before that silence.
library;

import 'dart:io';

import 'package:ccrlogger/analyzer/bridge/bridge_protocol.dart';

/// One SOLO line as it arrived.
class CapturedLine {
  /// Seconds since the capture started, as a [Duration].
  final Duration elapsed;

  /// The line with its `\xNN` escapes decoded and the trailing CR LF gone;
  /// internal runs of spaces are kept as they were.
  final String line;

  const CapturedLine(this.elapsed, this.line);
}

/// A silence in the data, longer than the capture tool's 0.5 s threshold.
class CaptureGap {
  /// When the data resumed.
  final Duration endsAt;

  /// How long the silence lasted.
  final Duration length;

  const CaptureGap(this.endsAt, this.length);
}

class SoloCaptureLog {
  final List<CapturedLine> lines;
  final List<CaptureGap> gaps;

  const SoloCaptureLog(this.lines, this.gaps);
}

/// `<sec> <wall> <kind> <rest>`. The seconds are right-aligned, so leading
/// spaces are allowed; every other separator is exactly one space, which
/// keeps the runs of spaces inside an RX payload.
final RegExp _captureLine = RegExp(r'^\s*(\d+\.\d+) (\S+) (\S+)(?: (.*))?$');

final RegExp _hexEscape = RegExp(r'\\x([0-9a-fA-F]{2})');
final RegExp _trailingCrLf = RegExp(r'[\r\n]+$');

Duration _seconds(String s) =>
    Duration(milliseconds: (double.parse(s) * 1000).round());

/// Unescapes `\xNN` in RX payloads and strips the trailing CR LF. Lines of
/// other kinds (ERROR, MARK, STOP, ...) are skipped.
SoloCaptureLog readSoloCaptureLog(String path) {
  final lines = <CapturedLine>[];
  final gaps = <CaptureGap>[];
  for (final raw in File(path).readAsLinesSync()) {
    final m = _captureLine.firstMatch(raw);
    if (m == null) continue;
    final elapsed = _seconds(m.group(1)!);
    final payload = m.group(4) ?? '';
    switch (m.group(3)) {
      case 'RX':
        final text = payload
            .replaceAllMapped(
              _hexEscape,
              (e) => String.fromCharCode(int.parse(e.group(1)!, radix: 16)),
            )
            .replaceAll(_trailingCrLf, '');
        lines.add(CapturedLine(elapsed, text));
      case 'GAP':
        gaps.add(CaptureGap(elapsed, _seconds(payload.trim())));
    }
  }
  return SoloCaptureLog(lines, gaps);
}

/// The record a bridge would build for [gap]: the held line is the last line
/// that arrived before the gap's silence, the window is every line in the 30
/// s up to it (offsets in ms relative to the held line, so zero or negative),
/// and `upMs` is the held line's elapsed ms.
///
/// The GAP line is written before the first RX line of the data that ends
/// the silence, so no line before the gap has an `elapsed` at or after
/// [CaptureGap.endsAt].
BridgeRecord recordBeforeGap(
  SoloCaptureLog log,
  CaptureGap gap, {
  String rid = 'cap-1',
  int boot = 1,
  bool live = true,
  int wallMs = 0,
}) {
  final heldIndex = log.lines.lastIndexWhere((l) => l.elapsed < gap.endsAt);
  if (heldIndex < 0) {
    throw StateError('no line before the gap that ends at ${gap.endsAt}');
  }
  final held = log.lines[heldIndex];
  final from = held.elapsed - const Duration(seconds: 30);
  return BridgeRecord(
    rid: rid,
    boot: boot,
    upMs: held.elapsed.inMilliseconds,
    wallMs: wallMs,
    live: live,
    window: [
      for (var i = 0; i < heldIndex; i++)
        if (log.lines[i].elapsed >= from)
          BridgeWindowLine(
            (log.lines[i].elapsed - held.elapsed).inMilliseconds,
            log.lines[i].line,
          ),
    ],
    heldLine: held.line,
  );
}
