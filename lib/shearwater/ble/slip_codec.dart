/// BLE-specific SLIP codec for Shearwater dive computers.
///
/// On BLE, each SLIP frame is split into 32-byte chunks with a 2-byte
/// header: [total_frame_count, frame_index]. This layer handles that
/// chunking on top of the underlying SLIP encode/decode.
library;

import 'dart:typed_data';

import '../parser/slip_decoder.dart';

/// Maximum BLE characteristic write size (bytes).
const int _bleFrameSize = 32;

/// Overhead per BLE frame: [nframes, frame_index].
const int _bleHeaderSize = 2;

/// Usable payload per BLE frame.
const int _blePayloadSize = _bleFrameSize - _bleHeaderSize;

/// BLE SLIP codec: encodes/decodes SLIP frames with BLE chunking.
class BleSlipCodec {
  /// Encode [payload] into BLE frames.
  ///
  /// The payload is SLIP-encoded (with END terminator), then split into
  /// 32-byte BLE frames. Each frame has a 2-byte header:
  /// `[total_frames, frame_index]`.
  static List<Uint8List> encode(Uint8List payload) {
    final slipData = slipEncode(payload);

    // Calculate number of frames needed.
    final nframes = (slipData.length + _blePayloadSize - 1) ~/ _blePayloadSize;

    final frames = <Uint8List>[];
    var offset = 0;

    for (var i = 0; i < nframes; i++) {
      final remaining = slipData.length - offset;
      final chunkSize = remaining < _blePayloadSize ? remaining : _blePayloadSize;
      final frame = Uint8List(chunkSize + _bleHeaderSize);
      frame[0] = nframes;
      frame[1] = i;
      frame.setRange(_bleHeaderSize, _bleHeaderSize + chunkSize,
          slipData, offset);
      frames.add(frame);
      offset += chunkSize;
    }

    return frames;
  }

  /// Decode a list of BLE [frames] into the original payload.
  ///
  /// Strips the 2-byte BLE header from each frame, concatenates the
  /// SLIP data, and SLIP-decodes the result.
  static Uint8List decode(List<Uint8List> frames) {
    final builder = BytesBuilder(copy: false);
    for (final frame in frames) {
      if (frame.length > _bleHeaderSize) {
        builder.add(frame.sublist(_bleHeaderSize));
      }
    }
    return slipDecode(builder.toBytes());
  }
}
