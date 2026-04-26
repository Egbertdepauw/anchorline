import 'dart:typed_data';

/// Read an unsigned 8-bit value.
int uint8(Uint8List data, int offset) => data[offset];

/// Read a big-endian unsigned 16-bit value.
int uint16BE(Uint8List data, int offset) =>
    (data[offset] << 8) | data[offset + 1];

/// Read a big-endian unsigned 24-bit value.
int uint24BE(Uint8List data, int offset) =>
    (data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2];

/// Read a big-endian unsigned 32-bit value.
int uint32BE(Uint8List data, int offset) =>
    (data[offset] << 24) |
    (data[offset + 1] << 16) |
    (data[offset + 2] << 8) |
    data[offset + 3];

/// Read a signed 8-bit value (-128 to 127).
int int8(Uint8List data, int offset) {
  final v = data[offset];
  return v < 128 ? v : v - 256;
}

/// Convert a hex string (e.g. "B89641E4") to bytes.
Uint8List hexToBytes(String hex) {
  final length = hex.length ~/ 2;
  final result = Uint8List(length);
  for (var i = 0; i < length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}
