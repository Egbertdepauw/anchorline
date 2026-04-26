import 'dart:typed_data';

import 'package:ccrlogger/shearwater/ble/slip_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BleSlipCodec.encode', () {
    test('encodes small payload into single BLE frame', () {
      // RDBI request for serial: payload = [0x22, 0x80, 0x10]
      // After SLIP encoding (no special chars): [0x22, 0x80, 0x10, 0xC0]
      // Total SLIP data: 4 bytes. Fits in one 32-byte frame.
      // BLE frame: [0x01, 0x00, 0x22, 0x80, 0x10, 0xC0]
      final payload = Uint8List.fromList([0x22, 0x80, 0x10]);
      final frames = BleSlipCodec.encode(payload);

      expect(frames, hasLength(1));
      expect(frames[0][0], equals(1)); // nframes
      expect(frames[0][1], equals(0)); // frame index
      // Remainder is SLIP-encoded payload + END
      expect(frames[0].sublist(2), equals([0x22, 0x80, 0x10, 0xC0]));
    });

    test('encodes payload with SLIP escapes', () {
      // Payload containing 0xC0 → must be escaped as 0xDB 0xDC
      final payload = Uint8List.fromList([0x01, 0xC0, 0x02]);
      final frames = BleSlipCodec.encode(payload);

      expect(frames, hasLength(1));
      // SLIP encoded: [0x01, 0xDB, 0xDC, 0x02, 0xC0]
      expect(frames[0].sublist(2), equals([0x01, 0xDB, 0xDC, 0x02, 0xC0]));
    });

    test('splits large payload into multiple BLE frames', () {
      // Create payload that requires > 30 bytes when SLIP-encoded
      // (32 bytes per frame - 2 byte header = 30 data bytes)
      // 35 bytes of non-special data + END = 36 bytes SLIP → 2 frames
      final payload = Uint8List(35);
      for (var i = 0; i < 35; i++) {
        payload[i] = (i + 1) & 0x7F; // avoid special chars
      }
      final frames = BleSlipCodec.encode(payload);

      expect(frames.length, greaterThan(1));
      // First frame header
      expect(frames[0][0], equals(frames.length)); // nframes
      expect(frames[0][1], equals(0)); // first frame index 0
      // Second frame header
      expect(frames[1][0], equals(frames.length));
      expect(frames[1][1], equals(1)); // second frame index 1
    });

    test('each frame is at most 32 bytes', () {
      // Large payload
      final payload = Uint8List(200);
      final frames = BleSlipCodec.encode(payload);
      for (final frame in frames) {
        expect(frame.length, lessThanOrEqualTo(32));
      }
    });

    test('matches real trace: RDBI serial request', () {
      // From combined.txt line 1:
      // W (10 bytes): 01 00 ff 01 04 00 22 80 10 c0
      // This is a complete BLE write: [01, 00] header + SLIP data
      // The SLIP payload before encoding is the transfer packet:
      // [0xFF, 0x01, 0x04, 0x00, 0x22, 0x80, 0x10]
      final transferPacket =
          Uint8List.fromList([0xFF, 0x01, 0x04, 0x00, 0x22, 0x80, 0x10]);
      final frames = BleSlipCodec.encode(transferPacket);

      expect(frames, hasLength(1));
      expect(
        frames[0],
        equals([0x01, 0x00, 0xFF, 0x01, 0x04, 0x00, 0x22, 0x80, 0x10, 0xC0]),
      );
    });
  });

  group('BleSlipCodec.decode', () {
    test('decodes single-frame BLE response', () {
      // From combined.txt line 2 (RDBI serial response):
      // R (18 bytes): 01 00 01 ff 0c 00 62 80 10 42 38 39 36 34 31 45 34 c0
      final frame = Uint8List.fromList([
        0x01, 0x00, 0x01, 0xFF, 0x0C, 0x00, 0x62, 0x80, 0x10, //
        0x42, 0x38, 0x39, 0x36, 0x34, 0x31, 0x45, 0x34, 0xC0,
      ]);

      final payload = BleSlipCodec.decode([frame]);
      expect(
        payload,
        equals([
          0x01, 0xFF, 0x0C, 0x00, 0x62, 0x80, 0x10, //
          0x42, 0x38, 0x39, 0x36, 0x34, 0x31, 0x45, 0x34,
        ]),
      );
    });

    test('decodes multi-frame BLE response', () {
      // From combined.txt lines 12-13 (manifest block 1):
      // Frame 0: 02 00 01 ff 83 00 76 01 a5 c4 ...
      // Frame 1: 02 01 02 cc 69 d2 2d a9 ... c0
      // After decoding: strip BLE headers, concatenate, SLIP decode
      final frame0 = Uint8List.fromList([
        0x02, 0x00, 0x01, 0xFF, 0x83, 0x00, 0x76, 0x01, //
        0xA5, 0xC4, 0x02, 0xCE,
      ]);
      final frame1 = Uint8List.fromList([
        0x02, 0x01, 0x69, 0xE4, 0xA3, 0x56, 0xC0,
      ]);

      final payload = BleSlipCodec.decode([frame0, frame1]);
      // Should contain the SLIP-decoded concatenation of both frames' data
      expect(payload[0], equals(0x01)); // transfer header byte 0
      expect(payload[1], equals(0xFF)); // transfer header byte 1
      // Payload should contain A5 C4 (manifest header)
      expect(payload[6], equals(0xA5));
      expect(payload[7], equals(0xC4));
    });

    test('decodes SLIP escapes in BLE response', () {
      // A response containing escaped bytes
      final frame = Uint8List.fromList([
        0x01, 0x00, // BLE header
        0x01, 0xFF, 0x05, 0x00, // transfer header
        0xDB, 0xDC, // escaped 0xC0
        0xDB, 0xDD, // escaped 0xDB
        0xC0, // END
      ]);

      final payload = BleSlipCodec.decode([frame]);
      // Transfer header [0x01, 0xFF, 0x05, 0x00] + [0xC0, 0xDB]
      expect(payload, equals([0x01, 0xFF, 0x05, 0x00, 0xC0, 0xDB]));
    });

    test('round-trips encode then decode', () {
      final original = Uint8List.fromList(
          [0xFF, 0x01, 0x04, 0x00, 0x22, 0x80, 0x10]);
      final frames = BleSlipCodec.encode(original);
      final decoded = BleSlipCodec.decode(frames);
      expect(decoded, equals(original));
    });

    test('round-trips with SLIP special characters', () {
      final original = Uint8List.fromList(
          [0x01, 0xC0, 0xDB, 0xFF, 0xC0, 0xDB, 0x00]);
      final frames = BleSlipCodec.encode(original);
      final decoded = BleSlipCodec.decode(frames);
      expect(decoded, equals(original));
    });

    test('round-trips large payload across multiple frames', () {
      final original = Uint8List(200);
      for (var i = 0; i < 200; i++) {
        original[i] = i & 0xFF;
      }
      final frames = BleSlipCodec.encode(original);
      expect(frames.length, greaterThan(1));
      final decoded = BleSlipCodec.decode(frames);
      expect(decoded, equals(original));
    });
  });
}
