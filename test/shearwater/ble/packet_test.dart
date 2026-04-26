import 'dart:typed_data';

import 'package:ccrlogger/shearwater/ble/packet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Packet.buildRequest', () {
    test('builds RDBI request packet', () {
      // RDBI for serial: command payload = [0x22, 0x80, 0x10]
      // Transfer packet: [0xFF, 0x01, len+1=4, 0x00, 0x22, 0x80, 0x10]
      final packet =
          Packet.buildRequest(Uint8List.fromList([0x22, 0x80, 0x10]));
      expect(packet,
          equals([0xFF, 0x01, 0x04, 0x00, 0x22, 0x80, 0x10]));
    });

    test('builds download init request', () {
      // Download init: [0x35, 0x00, 0x34, addr4, addr3, addr2, addr1, size2, size1, size0]
      final payload = Uint8List.fromList(
          [0x35, 0x00, 0x34, 0xE0, 0x00, 0x00, 0x00, 0x00, 0x06, 0x00]);
      final packet = Packet.buildRequest(payload);
      expect(packet[0], equals(0xFF));
      expect(packet[1], equals(0x01));
      expect(packet[2], equals(11)); // len = 10 + 1
      expect(packet[3], equals(0x00));
      expect(packet.sublist(4), equals(payload));
    });

    test('builds download block request', () {
      final packet =
          Packet.buildRequest(Uint8List.fromList([0x36, 0x01]));
      expect(packet, equals([0xFF, 0x01, 0x03, 0x00, 0x36, 0x01]));
    });

    test('builds quit request', () {
      final packet =
          Packet.buildRequest(Uint8List.fromList([0x37]));
      expect(packet, equals([0xFF, 0x01, 0x02, 0x00, 0x37]));
    });
  });

  group('Packet.parseResponse', () {
    test('parses RDBI response', () {
      // Response: [0x01, 0xFF, 0x0C, 0x00, 0x62, 0x80, 0x10, ...]
      final raw = Uint8List.fromList([
        0x01, 0xFF, 0x0C, 0x00, //
        0x62, 0x80, 0x10, 0x42, 0x38, 0x39, 0x36, 0x34, 0x31, 0x45, 0x34,
      ]);
      final response = Packet.parseResponse(raw);

      expect(response.isValid, isTrue);
      expect(response.isNak, isFalse);
      expect(response.payload,
          equals([0x62, 0x80, 0x10, 0x42, 0x38, 0x39, 0x36, 0x34, 0x31, 0x45, 0x34]));
    });

    test('parses download init response', () {
      // [0x01, 0xFF, 0x04, 0x00, 0x75, 0x10, 0x82]
      final raw = Uint8List.fromList(
          [0x01, 0xFF, 0x04, 0x00, 0x75, 0x10, 0x82]);
      final response = Packet.parseResponse(raw);

      expect(response.isValid, isTrue);
      expect(response.payload, equals([0x75, 0x10, 0x82]));
      expect(response.command, equals(0x75));
    });

    test('parses download block response', () {
      final raw = Uint8List.fromList([
        0x01, 0xFF, 0x06, 0x00, //
        0x76, 0x01, 0xAA, 0xBB, 0xCC,
      ]);
      final response = Packet.parseResponse(raw);

      expect(response.isValid, isTrue);
      expect(response.command, equals(0x76));
      expect(response.payload, equals([0x76, 0x01, 0xAA, 0xBB, 0xCC]));
    });

    test('detects NAK response', () {
      // NAK: [0x01, 0xFF, 0x04, 0x00, 0x7F, 0x22, 0x01]
      final raw = Uint8List.fromList(
          [0x01, 0xFF, 0x04, 0x00, 0x7F, 0x22, 0x01]);
      final response = Packet.parseResponse(raw);

      expect(response.isNak, isTrue);
      expect(response.nakErrorCode, equals(0x01));
    });

    test('rejects packet with invalid header', () {
      final raw = Uint8List.fromList([0x00, 0x00, 0x00, 0x00]);
      final response = Packet.parseResponse(raw);
      expect(response.isValid, isFalse);
    });

    test('rejects too-short packet', () {
      final raw = Uint8List.fromList([0x01, 0xFF]);
      final response = Packet.parseResponse(raw);
      expect(response.isValid, isFalse);
    });
  });
}
