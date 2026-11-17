// Clears known identifying fields of a FIT dive file, in place, so the file
// keeps its layout and size:
//
//   dart run tool/anonymise_fit.dart <in.fit> <out.fit> [--serial 1000000001]
//
// What it does:
// * the serial: every serial field (file id, device info) becomes --serial,
//   and so does any other 4-byte integer equal to the file's original serial;
// * the position fields Subsurface declares (session, lap and record) become
//   the invalid marker;
// * every field of the user profile (message 3) becomes its invalid marker;
// * every string in messages 3, 2, 23 and 49 (user profile, device settings,
//   device info, file creator) is zeroed;
// * the file CRC is recomputed.
//
// What it does NOT do:
// * it does not sweep positions by value, so a position in a field Subsurface
//   does not declare stays;
// * it does not clear strings in other messages;
// * it does not inspect developer fields or repeated field numbers;
// * it does not touch heart rate or other physiological messages.
//
// Review its output by hand before committing any file that is not already
// public.
//
// It prints counts per message type, never values.
import 'dart:io';
import 'dart:typed_data';

import 'package:fit_reader/fit_reader.dart';

const _userProfile = 3;
const _lap = 19;
const _fileCreator = 49;

/// Position fields (sint32 semicircles), by global message number.
const _gpsFields = <int, Set<int>>{
  FitMesg.session: {3, 4, 29, 30, 31, 32, 38, 39},
  _lap: {3, 4, 5, 6, 27, 28, 29, 30},
  FitMesg.record: {0, 1},
};

/// Messages whose string fields are zeroed.
const _stringMessages = {
  _userProfile,
  FitMesg.deviceSettings,
  FitMesg.deviceInfo,
  _fileCreator,
};

/// Messages with a serial number in field 3.
const _serialMessages = {FitMesg.fileId, FitMesg.deviceInfo};
const _serialField = 3;

class AnonymiseReport {
  final Uint8List bytes;

  /// Global message number to what was changed there: `serial`, `gps`,
  /// `profile` or `string`, each with the number of fields.
  final Map<int, Map<String, int>> counts;

  const AnonymiseReport(this.bytes, this.counts);
}

int _elementSize(int baseType) {
  switch (baseType & 0x1F) {
    case 0x03 || 0x04 || 0x0B:
      return 2;
    case 0x05 || 0x06 || 0x08 || 0x0C:
      return 4;
    case 0x09 || 0x0E || 0x0F || 0x10:
      return 8;
    default:
      return 1;
  }
}

/// Writes the base type's invalid marker into every element of the field.
/// Returns whether any byte changed, so a field that already holds its
/// marker is not counted. This looks at the raw bytes: a string that starts
/// with a NUL still has what follows it.
bool _setInvalid(Uint8List out, FitField f, Endian e) {
  final d = ByteData.sublistView(out);
  final before = Uint8List.fromList(out.sublist(f.offset, f.offset + f.size));
  _write(d, f, e);
  for (var i = 0; i < f.size; i++) {
    if (out[f.offset + i] != before[i]) return true;
  }
  return false;
}

void _write(ByteData d, FitField f, Endian e) {
  final base = f.baseType & 0x1F;
  if (base == 0x07) {
    for (var i = 0; i < f.size; i++) {
      d.setUint8(f.offset + i, 0);
    }
    return;
  }
  final es = _elementSize(f.baseType);
  for (var p = f.offset; p + es <= f.offset + f.size; p += es) {
    switch (base) {
      case 0x01:
        d.setInt8(p, 0x7F);
      case 0x03:
        d.setInt16(p, 0x7FFF, e);
      case 0x05:
        d.setInt32(p, 0x7FFFFFFF, e);
      case 0x0E:
        d.setInt64(p, 0x7FFFFFFFFFFFFFFF, e);
      case 0x0A:
        d.setUint8(p, 0);
      case 0x0B:
        d.setUint16(p, 0, e);
      case 0x0C:
        d.setUint32(p, 0, e);
      case 0x10:
        d.setUint64(p, 0, e);
      default:
        // enum, uint8, byte, uint16, uint32, float32 (NaN), float64 (NaN),
        // uint64 and unknown types are all-ones.
        for (var i = 0; i < es; i++) {
          d.setUint8(p + i, 0xFF);
        }
    }
  }
}

bool _isInt32(int baseType) {
  final b = baseType & 0x1F;
  return b == 0x05 || b == 0x06 || b == 0x0C;
}

/// Anonymises [input]; throws [FitFormatException] if it is not a valid FIT
/// file. The result has the same length as [input].
AnonymiseReport anonymiseFit(Uint8List input, {int serial = 1000000001}) {
  final file = decodeFit(input);
  final headerSize = input[0];
  final dataEnd = headerSize + ByteData.sublistView(input).getUint32(4, Endian.little);
  if (input.length != dataEnd + 2) {
    throw const FitFormatException(
      'data after the end of the FIT file (chained files are not supported)',
    );
  }

  final out = Uint8List.fromList(input);
  final d = ByteData.sublistView(out);
  final counts = <int, Map<String, int>>{};
  void count(int global, String kind) {
    final m = counts.putIfAbsent(global, () => {});
    m[kind] = (m[kind] ?? 0) + 1;
  }

  // The file's own serial, read before anything is overwritten.
  int? original;
  for (final m in file.messages) {
    if (m.global == FitMesg.fileId) {
      final v = m.intField(_serialField);
      if (v != null && v != 0) original = v;
    }
  }

  for (final msg in file.messages) {
    final e = msg.bigEndian ? Endian.big : Endian.little;
    for (final f in msg.fields.values) {
      final isString = (f.baseType & 0x1F) == 0x07;
      if (msg.global == _userProfile) {
        if (_setInvalid(out, f, e)) count(msg.global, 'profile');
      } else if (_gpsFields[msg.global]?.contains(f.number) ?? false) {
        if (_setInvalid(out, f, e)) count(msg.global, 'gps');
      } else if (_serialMessages.contains(msg.global) &&
          f.number == _serialField &&
          _isInt32(f.baseType) &&
          f.size == 4) {
        if (f.value != null) {
          d.setUint32(f.offset, serial, e);
          count(msg.global, 'serial');
        }
      } else if (isString && _stringMessages.contains(msg.global)) {
        if (_setInvalid(out, f, e)) count(msg.global, 'string');
      } else if (original != null && _isInt32(f.baseType) && f.size % 4 == 0) {
        var hit = false;
        for (var p = f.offset; p < f.offset + f.size; p += 4) {
          if (d.getUint32(p, e) == original) {
            d.setUint32(p, serial, e);
            hit = true;
          }
        }
        if (hit) count(msg.global, 'serial');
      }
    }
  }

  d.setUint16(dataEnd, fitCrc16(out, 0, dataEnd), Endian.little);
  // Prove the result decodes, CRC included.
  decodeFit(out);
  return AnonymiseReport(out, counts);
}

String _label(int global) => switch (global) {
  FitMesg.fileId => 'file id',
  FitMesg.deviceSettings => 'device settings',
  FitMesg.session => 'session',
  _lap => 'lap',
  FitMesg.record => 'record',
  FitMesg.deviceInfo => 'device info',
  _userProfile => 'user profile',
  _fileCreator => 'file creator',
  _ => 'message',
};

Never _usage() {
  stderr.writeln(
    'usage: dart run tool/anonymise_fit.dart <in.fit> <out.fit> '
    '[--serial 1000000001]',
  );
  exit(64);
}

void main(List<String> args) {
  final rest = <String>[];
  var serial = 1000000001;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--serial') {
      if (i + 1 >= args.length) _usage();
      serial = int.tryParse(args[++i]) ?? _usage();
    } else {
      rest.add(args[i]);
    }
  }
  if (rest.length != 2) _usage();
  final AnonymiseReport report;
  try {
    report = anonymiseFit(File(rest[0]).readAsBytesSync(), serial: serial);
  } on FitFormatException catch (e) {
    stderr.writeln('not a valid FIT file: ${e.message}');
    exit(65);
  }
  File(rest[1]).writeAsBytesSync(report.bytes);
  final keys = report.counts.keys.toList()..sort();
  for (final g in keys) {
    for (final e in report.counts[g]!.entries) {
      stdout.writeln('message $g (${_label(g)}): ${e.key} x${e.value}');
    }
  }
  if (keys.isEmpty) stdout.writeln('nothing to change');
}
