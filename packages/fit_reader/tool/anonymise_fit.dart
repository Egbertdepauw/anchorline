// Strips what identifies a person or a device out of a FIT dive file, in
// place, so the file keeps its layout and size:
//
//   dart run tool/anonymise_fit.dart <in.fit> <out.fit> [--serial 1000000001]
//
// * every serial field (file id, device info) becomes --serial, and so does
//   any other 4-byte integer holding the file's original serial, because
//   undocumented messages may repeat it;
// * every position Subsurface declares (session, lap and record) becomes
//   the invalid marker;
// * every field of the user profile (message 3) becomes its invalid marker;
// * every string in the user profile, device settings, device info and file
//   creator messages is zeroed;
// * the file CRC is recomputed.
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

class _Field {
  final int number;
  final int baseType;
  final int size;
  final int offset;
  const _Field(this.number, this.baseType, this.size, this.offset);
}

class _Message {
  final int global;
  final Endian endian;
  final List<_Field> fields;
  const _Message(this.global, this.endian, this.fields);
}

/// Walks the records and lists every data message's fields with the byte
/// offset and the byte order they were written in. [decodeFit] has already
/// vetted the file, so this only follows the layout.
List<_Message> _walk(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  final headerSize = bytes[0];
  final dataEnd = headerSize + d.getUint32(4, Endian.little);
  final defs = <int, (int, Endian, List<(int, int, int)>, int)>{};
  final out = <_Message>[];
  var pos = headerSize;

  void data(int local) {
    final def = defs[local]!;
    final fields = <_Field>[];
    for (final f in def.$3) {
      fields.add(_Field(f.$1, f.$3, f.$2, pos));
      pos += f.$2;
    }
    pos += def.$4;
    out.add(_Message(def.$1, def.$2, fields));
  }

  while (pos < dataEnd) {
    final rh = bytes[pos++];
    if (rh & 0x80 != 0) {
      data((rh >> 5) & 0x03);
    } else if (rh & 0x40 != 0) {
      final local = rh & 0x0F;
      final endian = bytes[pos + 1] == 0 ? Endian.little : Endian.big;
      final global = d.getUint16(pos + 2, endian);
      final count = bytes[pos + 4];
      pos += 5;
      final fields = <(int, int, int)>[];
      for (var i = 0; i < count; i++) {
        fields.add((bytes[pos], bytes[pos + 1], bytes[pos + 2]));
        pos += 3;
      }
      var devSize = 0;
      if (rh & 0x20 != 0) {
        final devCount = bytes[pos++];
        for (var i = 0; i < devCount; i++) {
          devSize += bytes[pos + 1];
          pos += 3;
        }
      }
      defs[local] = (global, endian, fields, devSize);
    } else {
      data(rh & 0x0F);
    }
  }
  return out;
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
void _setInvalid(ByteData d, _Field f, Endian e) {
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
  final messages = _walk(input);
  assert(messages.length == file.messages.length);

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

  for (var i = 0; i < messages.length; i++) {
    final msg = messages[i];
    final decoded = file.messages[i];
    for (final f in msg.fields) {
      final valid = decoded.fields[f.number]?.value != null;
      if (!valid) continue;
      final isString = (f.baseType & 0x1F) == 0x07;
      if (msg.global == _userProfile) {
        _setInvalid(d, f, msg.endian);
        count(msg.global, 'profile');
      } else if (_gpsFields[msg.global]?.contains(f.number) ?? false) {
        _setInvalid(d, f, msg.endian);
        count(msg.global, 'gps');
      } else if (_serialMessages.contains(msg.global) &&
          f.number == _serialField &&
          _isInt32(f.baseType) &&
          f.size == 4) {
        d.setUint32(f.offset, serial, msg.endian);
        count(msg.global, 'serial');
      } else if (isString && _stringMessages.contains(msg.global)) {
        _setInvalid(d, f, msg.endian);
        count(msg.global, 'string');
      } else if (original != null && _isInt32(f.baseType) && f.size % 4 == 0) {
        var hit = false;
        for (var p = f.offset; p < f.offset + f.size; p += 4) {
          if (d.getUint32(p, msg.endian) == original) {
            d.setUint32(p, serial, msg.endian);
            hit = true;
          }
        }
        if (hit) count(msg.global, 'serial');
      }
    }
  }

  final headerSize = out[0];
  final dataEnd = headerSize + d.getUint32(4, Endian.little);
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
