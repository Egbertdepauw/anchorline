/// Turns a raw serial byte stream into text lines.
///
/// Serial reads arrive in arbitrary chunks: a line can be split over
/// several chunks and one chunk can hold several lines. [SerialLineBuffer]
/// keeps the partial tail between chunks and emits complete lines split
/// on `\r?\n`, terminator stripped. A lone `\r` is kept as part of the
/// line, matching the `\r?\n` contract of [AnalyzerTransport].
///
/// Lines are decoded as UTF-8 only once complete, so a multi-byte
/// character split across chunks still decodes correctly. Malformed bytes
/// become U+FFFD instead of throwing: line noise must never kill a
/// session.
///
/// Pure Dart, shared by every byte-oriented transport.
library;

import 'dart:convert';

class SerialLineBuffer {
  SerialLineBuffer({this.maxLineLength = 4096});

  /// A partial line longer than this is dropped. Guards against a device
  /// that streams bytes without ever sending a newline (wrong baud rate).
  final int maxLineLength;

  static const int _lf = 0x0A;
  static const int _cr = 0x0D;

  final List<int> _pending = [];

  /// Bytes of the current, not yet terminated line.
  int get pendingLength => _pending.length;

  /// Adds one chunk and returns the lines it completed, in order. Empty
  /// lines (blank `\r\n`) are skipped.
  List<String> add(List<int> chunk) {
    final out = <String>[];
    for (final b in chunk) {
      if (b == _lf) {
        var end = _pending.length;
        if (end > 0 && _pending[end - 1] == _cr) end--;
        if (end > 0) {
          out.add(utf8.decode(_pending.sublist(0, end), allowMalformed: true));
        }
        _pending.clear();
      } else {
        if (_pending.length >= maxLineLength) _pending.clear();
        _pending.add(b);
      }
    }
    return out;
  }

  /// Drops any partial line (on reconnect).
  void clear() => _pending.clear();
}
