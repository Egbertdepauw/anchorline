import 'dart:convert';
import 'dart:typed_data';

import '../envelope.dart';

/// One event of a download's I/O, as Anchorline's C layer records it
/// (`native/anchorline_io.h`): a kind letter, when it happened, and the
/// payload in the C layer's packed form.
///
/// The kinds are `W` (bytes written), `R` (bytes read; none when the read
/// timed out or failed), `E` (the call just before failed: i32 its
/// `dc_status_t`), `P` (an input purge: u32 bytes dropped), `C` (a
/// characteristic read or write: u8 direction, u8 UUID length, the UUID, the
/// value), `I` (an unsupported ioctl: u32 request), `S` (a sleep: u32 ms),
/// `T` (the read timeout: i32 ms) and `X` (anything else, as ASCII text). A
/// replay serves `W`, `R` and `C`, and an `E` gives the call before it that
/// status again.
final class LibdcIoEvent {
  LibdcIoEvent(this.kind, List<int> payload, {this.micros})
    : payload = Uint8List.fromList(payload) {
    if (kind.length != 1 || kind.codeUnitAt(0) > 0x7f) {
      throw ArgumentError.value(kind, 'kind', 'not one ASCII letter');
    }
  }

  /// One ASCII letter.
  final String kind;

  /// Microseconds since the link was created, or null when the source had no
  /// timestamps (a `.combined.txt` trace).
  final int? micros;

  final Uint8List payload;

  static const _header = 13; // u8 kind, u64 micros, u32 length

  /// The C layer's packed events: big-endian `u8 kind`, `u64 micros`,
  /// `u32 length`, the payload. Throws [FormatException] when the last
  /// event runs past the end.
  static List<LibdcIoEvent> unpackAll(Uint8List packed) {
    final view = ByteData.sublistView(packed);
    final events = <LibdcIoEvent>[];
    var offset = 0;
    while (offset < packed.length) {
      if (packed.length - offset < _header) {
        throw const FormatException('A recording event runs past the end');
      }
      final length = view.getUint32(offset + 9);
      if (length > packed.length - offset - _header) {
        throw const FormatException('A recording event runs past the end');
      }
      events.add(
        LibdcIoEvent(
          String.fromCharCode(packed[offset]),
          Uint8List.sublistView(
            packed,
            offset + _header,
            offset + _header + length,
          ),
          micros: view.getUint64(offset + 1),
        ),
      );
      offset += _header + length;
    }
    return events;
  }

  /// [events] in the C layer's packed layout. A missing timestamp is 0.
  static Uint8List packAll(List<LibdcIoEvent> events) {
    final out = BytesBuilder(copy: false);
    for (final e in events) {
      final header = ByteData(_header)
        ..setUint8(0, e.kind.codeUnitAt(0))
        ..setUint64(1, e.micros ?? 0)
        ..setUint32(9, e.payload.length);
      out
        ..add(header.buffer.asUint8List())
        ..add(e.payload);
    }
    return out.toBytes();
  }

  /// The event as one line of a recording's text, without the timestamp.
  String describe() {
    final p = payload;
    switch (kind) {
      case 'P' when p.length == 4:
        return 'P input ${_u32(p)} bytes dropped';
      case 'S' when p.length == 4:
        return 'S ${_u32(p)}';
      case 'T' || 'E' when p.length == 4:
        return '$kind ${ByteData.sublistView(p).getInt32(0)}';
      case 'I' when p.length == 4:
        return 'I ${_u32(p).toRadixString(16).padLeft(8, '0')} unsupported';
      case 'X' when p.every((b) => b >= 0x20 && b < 0x7f):
        return 'X ${ascii.decode(p)}';
      case 'C'
          when p.length >= 2 &&
              (p[0] == _dirRead || p[0] == _dirWrite) &&
              p[1] == _uuidLength &&
              p.length >= 2 + _uuidLength &&
              _isUuid(p.sublist(2, 2 + _uuidLength)):
        final value = p.sublist(2 + _uuidLength);
        final direction = p[0] == _dirRead ? 'read' : 'write';
        final uuid = ascii.decode(p.sublist(2, 2 + _uuidLength));
        return 'C $direction $uuid (${value.length} bytes):${_hex(value)}';
      default:
        return '$kind (${p.length} bytes):${_hex(p)}';
    }
  }

  /// The event as one line of a recording's text.
  String toLine() {
    final m = micros;
    if (m == null) return describe();
    final seconds = m ~/ 1000000;
    final fraction = (m % 1000000).toString().padLeft(6, '0');
    return '[$seconds.$fraction] ${describe()}';
  }

  static final _timestamped = RegExp(r'^\[(\d+)\.(\d{6})\] (.*)$');
  static final _bytes = RegExp(r'^([A-Z]) \((\d+) bytes?\):(.*)$');
  static final _characteristic = RegExp(
    r'^C (read|write) ([0-9A-Fa-f-]{36}) \((\d+) bytes?\):(.*)$',
  );
  static final _purge = RegExp(r'^P input (\d+) bytes? dropped$');
  static final _number = RegExp(r'^([STE]) (-?\d+)$');
  static final _ioctl = RegExp(r'^I ([0-9A-Fa-f]{1,8}) unsupported$');

  /// Reads one event line: `[12.345678] W (2 bytes): 01 02`, with or without
  /// the timestamp. Throws [FormatException] on anything else.
  static LibdcIoEvent parseLine(String line) {
    int? micros;
    var rest = line;
    final t = _timestamped.firstMatch(line);
    if (t != null) {
      micros = int.parse(t.group(1)!) * 1000000 + int.parse(t.group(2)!);
      rest = t.group(3)!;
    }
    final c = _characteristic.firstMatch(rest);
    if (c != null) {
      final value = _parseHex(c.group(4)!, int.parse(c.group(3)!), line);
      return LibdcIoEvent('C', [
        c.group(1) == 'read' ? _dirRead : _dirWrite,
        _uuidLength,
        ...ascii.encode(c.group(2)!.toLowerCase()),
        ...value,
      ], micros: micros);
    }
    final b = _bytes.firstMatch(rest);
    if (b != null) {
      return LibdcIoEvent(
        b.group(1)!,
        _parseHex(b.group(3)!, int.parse(b.group(2)!), line),
        micros: micros,
      );
    }
    final p = _purge.firstMatch(rest);
    if (p != null) {
      return LibdcIoEvent(
        'P',
        _u32Bytes(int.parse(p.group(1)!)),
        micros: micros,
      );
    }
    final n = _number.firstMatch(rest);
    if (n != null) {
      final value = int.parse(n.group(2)!);
      final bytes = ByteData(4);
      if (n.group(1) != 'S') {
        bytes.setInt32(0, value);
      } else {
        bytes.setUint32(0, value);
      }
      return LibdcIoEvent(
        n.group(1)!,
        bytes.buffer.asUint8List(),
        micros: micros,
      );
    }
    final i = _ioctl.firstMatch(rest);
    if (i != null) {
      return LibdcIoEvent(
        'I',
        _u32Bytes(int.parse(i.group(1)!, radix: 16)),
        micros: micros,
      );
    }
    if (rest.startsWith('X ')) {
      return LibdcIoEvent('X', ascii.encode(rest.substring(2)), micros: micros);
    }
    throw FormatException('Not a recording event', line);
  }

  static const _dirRead = 1; // DC_IOCTL_DIR_READ
  static const _dirWrite = 2; // DC_IOCTL_DIR_WRITE
  static const _uuidLength = 36;

  static bool _isUuid(List<int> bytes) => bytes.every(
    (b) => (b >= 0x30 && b <= 0x39) || (b >= 0x61 && b <= 0x66) || b == 0x2d,
  );

  static int _u32(Uint8List p) => ByteData.sublistView(p).getUint32(0);

  static Uint8List _u32Bytes(int value) =>
      (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

  static String _hex(List<int> bytes) {
    final out = StringBuffer();
    for (final b in bytes) {
      out
        ..write(' ')
        ..write(b.toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }

  static Uint8List _parseHex(String text, int expected, String line) {
    final tokens = text.trim().isEmpty
        ? const <String>[]
        : text.trim().split(RegExp(r'\s+'));
    if (tokens.length != expected) {
      throw FormatException(
        'The line says $expected bytes but holds ${tokens.length}',
        line,
      );
    }
    return Uint8List.fromList([
      for (final t in tokens)
        if (t.length == 2)
          int.tryParse(t, radix: 16) ??
              (throw FormatException('Not a hex byte: $t', line))
        else
          throw FormatException('Not a hex byte: $t', line),
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is LibdcIoEvent &&
      other.kind == kind &&
      other.micros == micros &&
      _equalBytes(other.payload, payload);

  @override
  int get hashCode => Object.hash(kind, micros, Object.hashAll(payload));

  @override
  String toString() => 'LibdcIoEvent(${toLine()})';
}

bool _equalBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What a download leaves behind, to share when a computer misbehaves (spec
/// section 9) and to replay in tests.
///
/// [events] is empty unless the download recorded; [header], [log] and
/// [envelopes] are always filled, so a failed download can be shared too.
///
/// The text form:
///
/// ```
/// # Anchorline download recording 1
/// # descriptor <vendor>|<product>|<family>|<model>
/// # advertised <name>
/// # libdivecomputer <commit>
/// [12.345678] W (10 bytes): 01 00 ff ...
/// [12.401002] R (18 bytes): 01 00 01 ...
/// [13.000000] P input 40 bytes dropped
/// [13.100000] C read 00002a29-0000-1000-8000-00805f9b34fb (8 bytes): ...
/// [13.200000] S 300
/// [13.200001] T 3000
/// [13.200002] I 40047801 unsupported
/// [13.200003] X configure 115200 8N1
/// [13.300000] R (0 bytes):
/// [13.300001] E -7
/// # log
/// <libdivecomputer log lines>
/// # envelope <base64 of LibdcEnvelope.encode()>
/// # end
/// ```
///
/// [header] holds the header lines without their `# `, and not the first
/// line. The app adds header lines of its own.
class LibdcRecording {
  LibdcRecording({
    List<String> header = const [],
    List<LibdcIoEvent> events = const [],
    List<String> log = const [],
    List<LibdcEnvelope> envelopes = const [],
  }) : header = List.unmodifiable(header),
       events = List.unmodifiable(events),
       log = List.unmodifiable(log),
       envelopes = List.unmodifiable(envelopes);

  final List<String> header;
  final List<LibdcIoEvent> events;
  final List<String> log;
  final List<LibdcEnvelope> envelopes;

  static const _magic = 'Anchorline download recording';
  static const _version = 1;

  /// The name in the `advertised` header line, or null.
  String? get advertisedName {
    for (final h in header) {
      if (h.startsWith('advertised ')) return h.substring('advertised '.length);
    }
    return null;
  }

  String toText() {
    final out = StringBuffer()..writeln('# $_magic $_version');
    for (final h in header) {
      out.writeln('# $h');
    }
    for (final e in events) {
      out.writeln(e.toLine());
    }
    out.writeln('# log');
    for (final line in log) {
      out.writeln(line);
    }
    for (final e in envelopes) {
      out.writeln('# envelope ${base64.encode(e.encode())}');
    }
    out.writeln('# end');
    return out.toString();
  }

  /// Reads [toText]'s format, or a `.combined.txt` trace: its
  /// `W (<n> bytes): <hex>` and `R (<n> bytes): <hex>` lines, with no
  /// timestamps, header, log or envelopes. Throws [FormatException].
  static LibdcRecording parse(String text) {
    final header = <String>[];
    final events = <LibdcIoEvent>[];
    final log = <String>[];
    final envelopes = <LibdcEnvelope>[];
    var inLog = false;
    var first = true;
    final lines = const LineSplitter().convert(text);
    for (var n = 0; n < lines.length; n++) {
      final line = lines[n];
      final isFirst = first;
      first = false;
      if (line == '# end') break;
      if (line.startsWith('# envelope ')) {
        inLog = false;
        try {
          envelopes.add(
            LibdcEnvelope.decode(
              base64.decode(line.substring('# envelope '.length).trim()),
            ),
          );
        } on FormatException catch (e) {
          throw FormatException('Line ${n + 1}: ${e.message}', line);
        }
        continue;
      }
      if (inLog) {
        log.add(line);
        continue;
      }
      if (line == '# log') {
        inLog = true;
        continue;
      }
      if (line.startsWith('#')) {
        final content = line.substring(1).trimLeft();
        if (isFirst && content.startsWith(_magic)) {
          final version = int.tryParse(content.substring(_magic.length).trim());
          if (version == null || version > _version) {
            throw FormatException('Unknown recording version', line);
          }
          continue;
        }
        header.add(content);
        continue;
      }
      if (line.trim().isEmpty) continue;
      try {
        events.add(LibdcIoEvent.parseLine(line));
      } on FormatException catch (e) {
        throw FormatException('Line ${n + 1}: ${e.message}', line);
      }
    }
    return LibdcRecording(
      header: header,
      events: events,
      log: log,
      envelopes: envelopes,
    );
  }

  /// [events] in the C layer's packed layout, for `al_link_new_replay`.
  Uint8List toReplayEvents() => LibdcIoEvent.packAll(events);
}
