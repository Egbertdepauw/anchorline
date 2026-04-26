/// Gzip-based columnar packer for typed arrays.
///
/// Each column of sample data is stored as a gzipped blob of the
/// typed list's raw byte buffer. This gives good compression
/// (especially for repetitive dive data) while preserving exact
/// floating-point values.
library;

import 'dart:io';
import 'dart:typed_data';

class ColumnPacker {
  static final _encoder = ZLibEncoder(level: 6);
  static final _decoder = ZLibDecoder();

  // ── Float32 ──

  static Uint8List packFloat32(Float32List data) {
    return Uint8List.fromList(
        _encoder.convert(data.buffer.asUint8List()));
  }

  static Float32List unpackFloat32(Uint8List blob, int count) {
    if (count == 0) return Float32List(0);
    final bytes = Uint8List.fromList(_decoder.convert(blob));
    return bytes.buffer.asFloat32List();
  }

  // ── Int32 ──

  static Uint8List packInt32(Int32List data) {
    return Uint8List.fromList(
        _encoder.convert(data.buffer.asUint8List()));
  }

  static Int32List unpackInt32(Uint8List blob, int count) {
    if (count == 0) return Int32List(0);
    final bytes = Uint8List.fromList(_decoder.convert(blob));
    return bytes.buffer.asInt32List();
  }

  // ── Uint8 ──

  static Uint8List packUint8(Uint8List data) {
    return Uint8List.fromList(_encoder.convert(data));
  }

  static Uint8List unpackUint8(Uint8List blob, int count) {
    if (count == 0) return Uint8List(0);
    return Uint8List.fromList(_decoder.convert(blob));
  }
}
