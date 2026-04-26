/// Shearwater transfer packet envelope.
///
/// Request:  [0xFF, 0x01, payload_size+1, 0x00, ...payload]
/// Response: [0x01, 0xFF, payload_size+1, 0x00, ...payload]
/// NAK:      [0x01, 0xFF, length, 0x00, 0x7F, request_cmd, error_code]
library;

import 'dart:typed_data';

const int _nak = 0x7F;

/// Parsed response packet.
class ResponsePacket {
  /// Whether the packet has a valid transfer header.
  final bool isValid;

  /// The command/response payload (after stripping the 4-byte header).
  final Uint8List payload;

  /// Whether this is a NAK (negative acknowledgement).
  final bool isNak;

  /// NAK error code (only meaningful if [isNak] is true).
  final int nakErrorCode;

  ResponsePacket._({
    required this.isValid,
    required this.payload,
    this.isNak = false,
    this.nakErrorCode = 0,
  });

  /// The first byte of the payload (command/response code).
  int get command => payload.isNotEmpty ? payload[0] : 0;
}

/// Packet builder and parser for the Shearwater transfer protocol.
class Packet {
  /// Build a request packet from a command [payload].
  ///
  /// Returns `[0xFF, 0x01, payload.length + 1, 0x00, ...payload]`.
  static Uint8List buildRequest(Uint8List payload) {
    final packet = Uint8List(4 + payload.length);
    packet[0] = 0xFF;
    packet[1] = 0x01;
    packet[2] = payload.length + 1;
    packet[3] = 0x00;
    packet.setRange(4, 4 + payload.length, payload);
    return packet;
  }

  /// Parse a response packet (already SLIP-decoded, BLE headers stripped).
  ///
  /// Validates the `[0x01, 0xFF, length, 0x00]` header and extracts
  /// the payload. Detects NAK responses.
  static ResponsePacket parseResponse(Uint8List raw) {
    if (raw.length < 4 ||
        raw[0] != 0x01 ||
        raw[1] != 0xFF ||
        raw[3] != 0x00) {
      return ResponsePacket._(
        isValid: false,
        payload: Uint8List(0),
      );
    }

    final length = raw[2]; // includes status byte
    final payload = raw.sublist(4);

    // Validate declared length against actual.
    if (length < 1 || length - 1 != payload.length) {
      return ResponsePacket._(
        isValid: false,
        payload: Uint8List(0),
      );
    }

    // Check for NAK.
    if (payload.isNotEmpty && payload[0] == _nak) {
      return ResponsePacket._(
        isValid: true,
        payload: payload,
        isNak: true,
        nakErrorCode: payload.length >= 3 ? payload[2] : 0,
      );
    }

    return ResponsePacket._(
      isValid: true,
      payload: payload,
    );
  }
}
