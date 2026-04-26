import 'dart:typed_data';

/// SLIP special character codes.
const int _end = 0xC0;
const int _esc = 0xDB;
const int _escEnd = 0xDC;
const int _escEsc = 0xDD;

/// Decode a SLIP-framed byte sequence into the original payload.
///
/// Handles escaped END (0xDB 0xDC → 0xC0) and ESC (0xDB 0xDD → 0xDB).
/// Leading END bytes are skipped (empty packets ignored per SLIP spec).
/// Unknown escape sequences pass the byte through unchanged (per libdc).
Uint8List slipDecode(Uint8List frame) {
  final result = BytesBuilder(copy: false);
  var escaped = false;

  for (final byte in frame) {
    if (escaped) {
      escaped = false;
      switch (byte) {
        case _escEnd:
          result.addByte(_end);
        case _escEsc:
          result.addByte(_esc);
        default:
          // Unknown escape: pass through (matches libdc behavior).
          result.addByte(byte);
      }
      continue;
    }

    switch (byte) {
      case _end:
        // End of packet. Ignore if no data accumulated (leading ENDs).
        if (result.length > 0) return result.toBytes();
      case _esc:
        escaped = true;
      default:
        result.addByte(byte);
    }
  }

  return result.toBytes();
}

/// Encode a payload into a SLIP frame with END terminator.
///
/// END (0xC0) in data becomes 0xDB 0xDC. ESC (0xDB) becomes 0xDB 0xDD.
Uint8List slipEncode(Uint8List data) {
  final result = BytesBuilder(copy: false);

  for (final byte in data) {
    switch (byte) {
      case _end:
        result.addByte(_esc);
        result.addByte(_escEnd);
      case _esc:
        result.addByte(_esc);
        result.addByte(_escEsc);
      default:
        result.addByte(byte);
    }
  }

  result.addByte(_end);
  return result.toBytes();
}
