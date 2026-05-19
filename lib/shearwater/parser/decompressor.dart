import 'dart:typed_data';

/// Result of LRE decompression.
class LreResult {
  /// The decompressed bytes.
  final Uint8List data;

  /// Whether the end-of-stream marker (zero-length run) was encountered.
  final bool isFinal;

  LreResult(this.data, {required this.isFinal});
}

/// Decompress an LRE (Length-Run Encoding) compressed byte stream.
///
/// The algorithm interprets [compressed] as a stream of 9-bit values:
/// - Bit 8 set (0x100): literal byte (lower 8 bits appended to output)
/// - Bit 8 clear, value > 0: run of N zero bytes
/// - Bit 8 clear, value == 0: end of compressed stream
///
/// Any leftover bits at the end (fewer than 9) are ignored — this lets the
/// download path feed a partial / mid-stream buffer here every block to
/// look for the end marker without waiting for a 9-bit-aligned tail.
/// A complete stream is by construction 9-bit-aligned and contains the
/// `0` end marker, so the tail-bit tolerance only matters for streaming
/// callers that don't yet have the whole input.
///
/// Ported from `shearwater_common_decompress_lre` in libdivecomputer.
LreResult lreDecode(Uint8List compressed) {
  final nbits = compressed.length * 8;

  final buffer = BytesBuilder(copy: false);
  var isFinal = false;
  var offset = 0;

  while (offset + 9 <= nbits) {
    // Extract 9-bit value big-endian from the bit stream.
    final byteIndex = offset ~/ 8;
    final bitIndex = offset % 8;
    final shift = 16 - (bitIndex + 9);
    final value = ((compressed[byteIndex] << 8 |
                (byteIndex + 1 < compressed.length
                    ? compressed[byteIndex + 1]
                    : 0)) >>
            shift) &
        0x1FF;

    if (value & 0x100 != 0) {
      // Literal byte.
      buffer.addByte(value & 0xFF);
    } else if (value == 0) {
      // End of compressed stream.
      isFinal = true;
      break;
    } else {
      // Run of N zero bytes.
      buffer.add(Uint8List(value));
    }

    offset += 9;
  }

  return LreResult(buffer.toBytes(), isFinal: isFinal);
}

/// XOR-decode data in place.
///
/// Each byte at index >= 32 is XOR'd with the byte 32 positions before it.
/// The first 32 bytes pass through unchanged. This is cumulative: block N
/// depends on the already-decoded block N-1.
///
/// Ported from `shearwater_common_decompress_xor` in libdivecomputer.
void xorDecode(Uint8List data) {
  for (var i = 32; i < data.length; i++) {
    data[i] ^= data[i - 32];
  }
}

/// Full Shearwater decompression: LRE decode then XOR decode.
///
/// Returns the decompressed dive data.
Uint8List decompress(Uint8List compressed) {
  final lreResult = lreDecode(compressed);
  final data = lreResult.data;
  xorDecode(data);
  return data;
}
