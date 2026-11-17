import 'dart:convert';
import 'dart:typed_data';

/// Thrown when the bytes are not a well-formed FIT file.
class FitFormatException implements Exception {
  final String message;
  const FitFormatException(this.message);

  @override
  String toString() => 'FitFormatException: $message';
}

/// One field of a data message.
class FitField {
  final int number;

  /// The base type number as declared in the definition (e.g. 0x84 uint16).
  final int baseType;

  /// Size in bytes as declared in the definition.
  final int size;

  /// Byte offset of the value in the file.
  final int offset;

  /// An `int`, a `double`, a `String`, or a `List` for arrays. Null when the
  /// field holds its base type's invalid marker.
  final Object? value;

  const FitField({
    required this.number,
    required this.baseType,
    required this.size,
    required this.offset,
    required this.value,
  });
}

/// A decoded data message. Developer fields are skipped, not kept.
class FitMessage {
  final int global;

  /// Absolute FIT seconds, from field 253 or a compressed timestamp header.
  final int? timestamp;
  final Map<int, FitField> fields;

  const FitMessage({
    required this.global,
    required this.timestamp,
    required this.fields,
  });

  int? intField(int n) {
    final v = fields[n]?.value;
    return v is int ? v : null;
  }

  double? doubleField(int n) {
    final v = fields[n]?.value;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return null;
  }

  String? stringField(int n) {
    final v = fields[n]?.value;
    return v is String ? v : null;
  }
}

class FitFile {
  final int protocolVersion;
  final int profileVersion;
  final List<FitMessage> messages;

  const FitFile({
    required this.protocolVersion,
    required this.profileVersion,
    required this.messages,
  });
}

const _crcTable = <int>[
  0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401, //
  0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4401,
];

/// FIT's CRC-16 (polynomial 0xA001, nibble-wise) over `bytes[start, end)`.
int fitCrc16(Uint8List bytes, [int start = 0, int? end]) {
  var crc = 0;
  final stop = end ?? bytes.length;
  for (var i = start; i < stop; i++) {
    final b = bytes[i];
    crc = (crc >> 4) & 0x0FFF ^ _crcTable[crc & 0xF] ^ _crcTable[b & 0xF];
    crc =
        (crc >> 4) & 0x0FFF ^ _crcTable[crc & 0xF] ^ _crcTable[(b >> 4) & 0xF];
  }
  return crc;
}

/// Base type number (low 5 bits) to element size. Unknown types are treated
/// as raw bytes so an unexpected type can't derail the rest of the file.
int _elementSize(int baseType) {
  switch (baseType & 0x1F) {
    case 0x01: // sint8
    case 0x02: // uint8
    case 0x00: // enum
    case 0x07: // string
    case 0x0A: // uint8z
    case 0x0D: // byte
      return 1;
    case 0x03: // sint16
    case 0x04: // uint16
    case 0x0B: // uint16z
      return 2;
    case 0x05: // sint32
    case 0x06: // uint32
    case 0x08: // float32
    case 0x0C: // uint32z
      return 4;
    case 0x09: // float64
    case 0x0E: // sint64
    case 0x0F: // uint64
    case 0x10: // uint64z
      return 8;
    default:
      return 1;
  }
}

/// Reads one element; null if it is the base type's invalid marker.
Object? _readElement(ByteData d, int pos, int baseType, Endian e) {
  switch (baseType & 0x1F) {
    case 0x00:
    case 0x02:
    case 0x0D:
      final v = d.getUint8(pos);
      return v == 0xFF ? null : v;
    case 0x01:
      final v = d.getInt8(pos);
      return v == 0x7F ? null : v;
    case 0x03:
      final v = d.getInt16(pos, e);
      return v == 0x7FFF ? null : v;
    case 0x04:
      final v = d.getUint16(pos, e);
      return v == 0xFFFF ? null : v;
    case 0x05:
      final v = d.getInt32(pos, e);
      return v == 0x7FFFFFFF ? null : v;
    case 0x06:
      final v = d.getUint32(pos, e);
      return v == 0xFFFFFFFF ? null : v;
    case 0x08:
      final v = d.getFloat32(pos, e);
      return v.isNaN ? null : v;
    case 0x09:
      final v = d.getFloat64(pos, e);
      return v.isNaN ? null : v;
    case 0x0A:
      final v = d.getUint8(pos);
      return v == 0 ? null : v;
    case 0x0B:
      final v = d.getUint16(pos, e);
      return v == 0 ? null : v;
    case 0x0C:
      final v = d.getUint32(pos, e);
      return v == 0 ? null : v;
    case 0x0E:
      final v = d.getInt64(pos, e);
      return v == 0x7FFFFFFFFFFFFFFF ? null : v;
    case 0x0F:
      final v = d.getUint64(pos, e);
      return v == -1 ? null : v; // 0xFFFFFFFFFFFFFFFF as a signed int
    case 0x10:
      final v = d.getUint64(pos, e);
      return v == 0 ? null : v;
    default:
      return d.getUint8(pos);
  }
}

Object? _readValue(ByteData d, int pos, int size, int baseType, Endian e) {
  if ((baseType & 0x1F) == 0x07) {
    final bytes = d.buffer.asUint8List(d.offsetInBytes + pos, size);
    var end = bytes.indexOf(0);
    if (end < 0) end = bytes.length;
    if (end == 0) return null;
    return utf8.decode(bytes.sublist(0, end), allowMalformed: true);
  }
  final es = _elementSize(baseType);
  if (size < es) return null;
  if (size == es) return _readElement(d, pos, baseType, e);
  final n = size ~/ es;
  final out = <Object>[];
  var anyValid = false;
  for (var i = 0; i < n; i++) {
    final v = _readElement(d, pos + i * es, baseType, e);
    if (v != null) anyValid = true;
    // Keep positions in an array; an invalid element reads as its raw
    // slot filled with -1 for ints so indices stay meaningful.
    out.add(v ?? -1);
  }
  return anyValid ? out : null;
}

class _FieldDef {
  final int number;
  final int size;
  final int baseType;
  const _FieldDef(this.number, this.size, this.baseType);
}

class _Definition {
  final int global;
  final Endian endian;
  final List<_FieldDef> fields;
  final int devSize;
  const _Definition(this.global, this.endian, this.fields, this.devSize);
}

/// Decodes a FIT file. Throws [FitFormatException] on a bad header, a
/// missing `.FIT` tag, a wrong header or file CRC, a truncated file, or a
/// data message with no definition. When [stopAfter] returns true for a
/// message, decoding ends there and the file CRC is not checked.
FitFile decodeFit(Uint8List bytes, {bool Function(FitMessage m)? stopAfter}) {
  if (bytes.length < 12) throw const FitFormatException('file too short');
  final headerSize = bytes[0];
  if (headerSize != 12 && headerSize != 14) {
    throw FitFormatException('bad header size $headerSize');
  }
  if (bytes.length < headerSize + 2) {
    throw const FitFormatException('file too short');
  }
  final d = ByteData.sublistView(bytes);
  if (bytes[8] != 0x2E ||
      bytes[9] != 0x46 ||
      bytes[10] != 0x49 ||
      bytes[11] != 0x54) {
    throw const FitFormatException('missing .FIT tag');
  }
  if (headerSize == 14) {
    final stored = d.getUint16(12, Endian.little);
    // A zero header CRC means "not computed".
    if (stored != 0 && stored != fitCrc16(bytes, 0, 12)) {
      throw const FitFormatException('header CRC mismatch');
    }
  }
  final protocolVersion = bytes[1];
  final profileVersion = d.getUint16(2, Endian.little);
  final dataSize = d.getUint32(4, Endian.little);
  final dataEnd = headerSize + dataSize;
  if (bytes.length < dataEnd + 2) {
    throw const FitFormatException('truncated file');
  }

  final defs = <int, _Definition>{};
  final messages = <FitMessage>[];
  var lastTimestamp = 0;
  var pos = headerSize;

  void need(int n) {
    if (pos + n > dataEnd) throw const FitFormatException('truncated record');
  }

  while (pos < dataEnd) {
    final rh = bytes[pos++];
    if (rh & 0x80 != 0) {
      // Compressed timestamp header: data message, local type in bits 5-6.
      final local = (rh >> 5) & 0x03;
      final offset = rh & 0x1F;
      var ts = (lastTimestamp & ~0x1F) + offset;
      if (offset < (lastTimestamp & 0x1F)) ts += 0x20;
      lastTimestamp = ts;
      final def = defs[local];
      if (def == null) {
        throw FitFormatException(
          'data message for undefined local type $local',
        );
      }
      final m = _readData(d, bytes, def, pos, dataEnd, ts);
      pos = m.$2;
      messages.add(m.$1);
      if (stopAfter != null && stopAfter(m.$1)) {
        return FitFile(
          protocolVersion: protocolVersion,
          profileVersion: profileVersion,
          messages: messages,
        );
      }
    } else if (rh & 0x40 != 0) {
      final local = rh & 0x0F;
      final hasDev = rh & 0x20 != 0;
      need(5);
      final endian = bytes[pos + 1] == 0 ? Endian.little : Endian.big;
      final global = d.getUint16(pos + 2, endian);
      final count = bytes[pos + 4];
      pos += 5;
      need(count * 3);
      final fields = <_FieldDef>[];
      for (var i = 0; i < count; i++) {
        fields.add(_FieldDef(bytes[pos], bytes[pos + 1], bytes[pos + 2]));
        pos += 3;
      }
      var devSize = 0;
      if (hasDev) {
        need(1);
        final devCount = bytes[pos++];
        need(devCount * 3);
        for (var i = 0; i < devCount; i++) {
          devSize += bytes[pos + 1];
          pos += 3;
        }
      }
      defs[local] = _Definition(global, endian, fields, devSize);
    } else {
      final local = rh & 0x0F;
      final def = defs[local];
      if (def == null) {
        throw FitFormatException(
          'data message for undefined local type $local',
        );
      }
      final m = _readData(d, bytes, def, pos, dataEnd, null);
      pos = m.$2;
      final ts = m.$1.timestamp;
      if (ts != null) lastTimestamp = ts;
      messages.add(m.$1);
      if (stopAfter != null && stopAfter(m.$1)) {
        return FitFile(
          protocolVersion: protocolVersion,
          profileVersion: profileVersion,
          messages: messages,
        );
      }
    }
  }

  final stored = d.getUint16(dataEnd, Endian.little);
  if (stored != fitCrc16(bytes, 0, dataEnd)) {
    throw const FitFormatException('file CRC mismatch');
  }
  return FitFile(
    protocolVersion: protocolVersion,
    profileVersion: profileVersion,
    messages: messages,
  );
}

(FitMessage, int) _readData(
  ByteData d,
  Uint8List bytes,
  _Definition def,
  int start,
  int dataEnd,
  int? compressedTs,
) {
  var pos = start;
  final fields = <int, FitField>{};
  for (final f in def.fields) {
    if (pos + f.size > dataEnd) {
      throw const FitFormatException('truncated record');
    }
    fields[f.number] = FitField(
      number: f.number,
      baseType: f.baseType,
      size: f.size,
      offset: pos,
      value: _readValue(d, pos, f.size, f.baseType, def.endian),
    );
    pos += f.size;
  }
  if (pos + def.devSize > dataEnd) {
    throw const FitFormatException('truncated record');
  }
  pos += def.devSize;
  final ts = fields[253]?.value;
  return (
    FitMessage(
      global: def.global,
      timestamp: ts is int ? ts : compressedTs,
      fields: fields,
    ),
    pos,
  );
}
