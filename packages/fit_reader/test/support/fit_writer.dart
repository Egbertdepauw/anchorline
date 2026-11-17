import 'dart:convert';
import 'dart:typed_data';

import 'package:fit_reader/fit_reader.dart';

/// One data message to write. Field values are `(baseType, value)` where
/// value is an int, a double, a String, or a `List<int>` for an array.
class FitMessageSpec {
  final int global;
  final Map<int, (int baseType, Object value)> fields;
  const FitMessageSpec(this.global, this.fields);
}

/// A developer field written (and declared) on every message.
class FitDevFieldSpec {
  final int number;
  final int devIndex;
  final List<int> bytes;
  const FitDevFieldSpec(this.number, this.devIndex, this.bytes);
}

int _size(int baseType) {
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

void _putElement(ByteData d, int pos, int baseType, Object v, Endian e) {
  switch (baseType & 0x1F) {
    case 0x01:
      d.setInt8(pos, v as int);
    case 0x00 || 0x02 || 0x0A || 0x0D:
      d.setUint8(pos, v as int);
    case 0x03:
      d.setInt16(pos, v as int, e);
    case 0x04 || 0x0B:
      d.setUint16(pos, v as int, e);
    case 0x05:
      d.setInt32(pos, v as int, e);
    case 0x06 || 0x0C:
      d.setUint32(pos, v as int, e);
    case 0x08:
      d.setFloat32(pos, (v as num).toDouble(), e);
    case 0x09:
      d.setFloat64(pos, (v as num).toDouble(), e);
    case 0x0E:
      d.setInt64(pos, v as int, e);
    case 0x0F || 0x10:
      d.setUint64(pos, v as int, e);
    default:
      throw ArgumentError('base type $baseType');
  }
}

Uint8List _encode(int baseType, Object value, Endian e) {
  if (value is String) {
    return Uint8List.fromList([...utf8.encode(value), 0]);
  }
  final items = value is List ? value : [value];
  final es = _size(baseType);
  final out = Uint8List(es * items.length);
  final d = ByteData.sublistView(out);
  for (var i = 0; i < items.length; i++) {
    _putElement(d, i * es, baseType, items[i] as Object, e);
  }
  return out;
}

/// Builds a FIT file. The CRC is correct unless [badCrc]; [truncateBy] cuts
/// that many bytes off the end; [skipDefinitions] leaves out the definition
/// messages. With [compressedTimestamps], a message whose field 253 is
/// within 31 seconds after the previous timestamp is written with a
/// compressed timestamp header and no field 253.
Uint8List buildFit(
  List<FitMessageSpec> messages, {
  bool bigEndian = false,
  bool compressedTimestamps = false,
  List<FitDevFieldSpec> devFields = const [],
  int headerSize = 14,
  bool badCrc = false,
  int truncateBy = 0,
  bool skipDefinitions = false,
}) {
  final e = bigEndian ? Endian.big : Endian.little;
  final body = BytesBuilder();
  final locals = <int, int>{};
  int? lastTs;

  for (final m in messages) {
    final ts = m.fields[253]?.$2 as int?;
    final compress =
        compressedTimestamps &&
        ts != null &&
        lastTs != null &&
        ts - lastTs >= 0 &&
        ts - lastTs < 32 &&
        locals.containsKey(m.global) &&
        m.fields.length > 1;
    final fields = Map.of(m.fields);
    if (compress) fields.remove(253);
    // A compressed-timestamp message has its own definition (no 253).
    final key = compress ? m.global + 0x10000 : m.global;
    final isNew = !locals.containsKey(key);
    final local = locals.putIfAbsent(key, () => locals.length);
    // A local type is 4 bits in a normal header and 2 bits in a compressed
    // timestamp header; a bigger one would silently corrupt the file.
    if (local >= 16) throw StateError('local type $local needs 4 bits');
    if (compressedTimestamps && local >= 4) {
      throw StateError('local type $local does not fit a compressed header');
    }
    final encoded = {
      for (final f in fields.entries)
        f.key: (f.value.$1, _encode(f.value.$1, f.value.$2, e)),
    };
    if (isNew && !skipDefinitions) {
      final hasDev = devFields.isNotEmpty;
      body.addByte(0x40 | (hasDev ? 0x20 : 0) | local);
      body.addByte(0);
      body.addByte(bigEndian ? 1 : 0);
      final g = ByteData(2)..setUint16(0, m.global, e);
      body.add(g.buffer.asUint8List());
      body.addByte(encoded.length);
      for (final f in encoded.entries) {
        body.add([f.key, f.value.$2.length, f.value.$1]);
      }
      if (hasDev) {
        body.addByte(devFields.length);
        for (final f in devFields) {
          body.add([f.number, f.bytes.length, f.devIndex]);
        }
      }
    }
    if (compress) {
      body.addByte(0x80 | (local << 5) | ((ts - 0) & 0x1F));
    } else {
      body.addByte(local);
    }
    for (final f in encoded.values) {
      body.add(f.$2);
    }
    for (final f in devFields) {
      body.add(f.bytes);
    }
    if (ts != null) lastTs = ts;
  }

  final data = body.toBytes();
  final header = ByteData(headerSize);
  header.setUint8(0, headerSize);
  header.setUint8(1, 0x20);
  header.setUint16(2, 2000, Endian.little);
  header.setUint32(4, data.length, Endian.little);
  header.setUint8(8, 0x2E);
  header.setUint8(9, 0x46);
  header.setUint8(10, 0x49);
  header.setUint8(11, 0x54);
  final hb = header.buffer.asUint8List();
  if (headerSize >= 14) {
    header.setUint16(12, fitCrc16(hb, 0, 12), Endian.little);
  }
  final all = BytesBuilder()
    ..add(hb)
    ..add(data);
  final withoutCrc = all.toBytes();
  var crc = fitCrc16(withoutCrc);
  if (badCrc) crc ^= 0x5A5A;
  final out = BytesBuilder()
    ..add(withoutCrc)
    ..add([crc & 0xFF, crc >> 8]);
  final bytes = out.toBytes();
  return truncateBy == 0
      ? bytes
      : Uint8List.sublistView(bytes, 0, bytes.length - truncateBy);
}
