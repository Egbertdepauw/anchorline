import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One entry for [buildZip].
class ZipSpec {
  ZipSpec(
    this.name,
    this.data, {
    this.deflate = false,
    this.dataDescriptor = false,
    this.zip64 = false,
    this.corruptCrc = false,
    this.encrypted = false,
    this.method,
  });

  final String name;
  final Uint8List data;
  final bool deflate;

  /// Sizes and CRC follow the data (flag bit 3); the local header holds zeros.
  final bool dataDescriptor;

  /// Writes this entry's sizes and offset in a Zip64 extra field.
  final bool zip64;

  final bool corruptCrc;
  final bool encrypted;

  /// Overrides the compression method written in the headers.
  final int? method;
}

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

int crc32Of(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Uint8List _raw(List<int> data) {
  final enc = ZLibEncoder(raw: true, level: 6);
  return Uint8List.fromList(enc.convert(data));
}

/// Builds a zip archive in memory. [zip64] forces Zip64 end records;
/// per-entry zip64 is set on the specs.
Uint8List buildZip(List<ZipSpec> specs, {bool zip64 = false}) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) =>
      b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void u64(BytesBuilder b, int v) {
    u32(b, v & 0xFFFFFFFF);
    u32(b, (v >> 32) & 0xFFFFFFFF);
  }

  for (final s in specs) {
    final name = utf8.encode(s.name);
    final payload = s.deflate ? _raw(s.data) : s.data;
    final method = s.method ?? (s.deflate ? 8 : 0);
    var crc = crc32Of(s.data);
    if (s.corruptCrc) crc ^= 1;
    final flags =
        (s.dataDescriptor ? 8 : 0) | (s.encrypted ? 1 : 0);
    final offset = out.length;

    // Local header.
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, flags);
    u16(out, method);
    u16(out, 0);
    u16(out, 0x21);
    u32(out, s.dataDescriptor ? 0 : crc);
    u32(out, s.dataDescriptor ? 0 : payload.length);
    u32(out, s.dataDescriptor ? 0 : s.data.length);
    u16(out, name.length);
    u16(out, 0);
    out.add(name);
    out.add(payload);
    if (s.dataDescriptor) {
      u32(out, 0x08074b50);
      u32(out, crc);
      u32(out, payload.length);
      u32(out, s.data.length);
    }

    // Central directory record.
    final extra = BytesBuilder();
    if (s.zip64) {
      u16(extra, 1);
      u16(extra, 24);
      u64(extra, s.data.length);
      u64(extra, payload.length);
      u64(extra, offset);
    }
    u32(central, 0x02014b50);
    u16(central, 45);
    u16(central, 45);
    u16(central, flags);
    u16(central, method);
    u16(central, 0);
    u16(central, 0x21);
    u32(central, crc);
    u32(central, s.zip64 ? 0xFFFFFFFF : payload.length);
    u32(central, s.zip64 ? 0xFFFFFFFF : s.data.length);
    u16(central, name.length);
    u16(central, extra.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, s.zip64 ? 0xFFFFFFFF : offset);
    central.add(name);
    central.add(extra.toBytes());
  }

  final cdOffset = out.length;
  final cd = central.toBytes();
  out.add(cd);
  if (zip64) {
    final z64Offset = out.length;
    u32(out, 0x06064b50);
    u64(out, 44);
    u16(out, 45);
    u16(out, 45);
    u32(out, 0);
    u32(out, 0);
    u64(out, specs.length);
    u64(out, specs.length);
    u64(out, cd.length);
    u64(out, cdOffset);
    u32(out, 0x07064b50);
    u32(out, 0);
    u64(out, z64Offset);
    u32(out, 1);
  }
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, zip64 ? 0xFFFF : specs.length);
  u16(out, zip64 ? 0xFFFF : specs.length);
  u32(out, zip64 ? 0xFFFFFFFF : cd.length);
  u32(out, zip64 ? 0xFFFFFFFF : cdOffset);
  u16(out, 0);
  return out.toBytes();
}
