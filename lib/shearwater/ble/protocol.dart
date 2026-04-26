/// High-level Shearwater protocol operations over BLE.
///
/// Implements RDBI, WDBI, and the download protocol on top of
/// a [BleIo] abstraction that provides raw BLE read/write.
library;

import 'dart:typed_data';

import '../parser/decompressor.dart';
import 'packet.dart';
import 'slip_codec.dart';

/// Abstract BLE I/O interface.
///
/// Implementations provide raw BLE characteristic read/write.
/// This abstraction allows the protocol layer to be tested
/// against mock/replay devices.
abstract class BleIo {
  /// Write a single BLE frame (characteristic write).
  Future<void> writeBytes(Uint8List data);

  /// Read the next set of BLE frames constituting a complete SLIP packet.
  ///
  /// For single-frame responses, returns a list with one element.
  /// For multi-frame responses, returns all frames in order.
  Future<List<Uint8List>> readFrames();
}

/// Shearwater protocol operations.
class ShearwaterProtocol {
  final BleIo _ble;

  ShearwaterProtocol(this._ble);

  /// Send a request and receive a response.
  ///
  /// Builds the transfer packet, SLIP+BLE encodes, writes, reads, decodes.
  Future<ResponsePacket> _transfer(Uint8List commandPayload) async {
    final requestPacket = Packet.buildRequest(commandPayload);
    final frames = BleSlipCodec.encode(requestPacket);

    // Write all BLE frames.
    for (final frame in frames) {
      await _ble.writeBytes(frame);
    }

    // Read response frames.
    final responseFrames = await _ble.readFrames();
    final decoded = BleSlipCodec.decode(responseFrames);
    return Packet.parseResponse(decoded);
  }

  /// Read Data By Identifier (RDBI).
  ///
  /// Sends `[0x22, id_hi, id_lo]` and returns the response data
  /// (after stripping the `[0x62, id_hi, id_lo]` response header).
  Future<Uint8List> rdbi(int id) async {
    final request = Uint8List.fromList([
      0x22,
      (id >> 8) & 0xFF,
      id & 0xFF,
    ]);

    final response = await _transfer(request);
    if (!response.isValid) {
      throw ProtocolException('Invalid RDBI response');
    }
    if (response.isNak) {
      throw ProtocolException(
          'RDBI NAK: error code 0x${response.nakErrorCode.toRadixString(16)}');
    }

    final payload = response.payload;
    if (payload.length < 3 ||
        payload[0] != 0x62 ||
        payload[1] != (id >> 8) & 0xFF ||
        payload[2] != id & 0xFF) {
      throw ProtocolException('Unexpected RDBI response');
    }

    return payload.sublist(3);
  }

  /// Write Data By Identifier (WDBI).
  Future<void> wdbi(int id, Uint8List data) async {
    final request = Uint8List(3 + data.length);
    request[0] = 0x2E;
    request[1] = (id >> 8) & 0xFF;
    request[2] = id & 0xFF;
    request.setRange(3, 3 + data.length, data);

    final response = await _transfer(request);
    if (!response.isValid) {
      throw ProtocolException('Invalid WDBI response');
    }
    if (response.isNak) {
      throw ProtocolException(
          'WDBI NAK: error code 0x${response.nakErrorCode.toRadixString(16)}');
    }
  }

  /// Download data from a flash memory address.
  ///
  /// Sends the init/block/quit download sequence.
  /// If [compressed], decompresses via LRE + XOR.
  /// Returns the complete downloaded (and optionally decompressed) data.
  Future<Uint8List> download({
    required int address,
    required int size,
    required bool compressed,
  }) async {
    // ── Init ──
    final initRequest = Uint8List.fromList([
      0x35,
      compressed ? 0x10 : 0x00,
      0x34,
      (address >> 24) & 0xFF,
      (address >> 16) & 0xFF,
      (address >> 8) & 0xFF,
      address & 0xFF,
      (size >> 16) & 0xFF,
      (size >> 8) & 0xFF,
      size & 0xFF,
    ]);

    final initResponse = await _transfer(initRequest);
    if (!initResponse.isValid) {
      throw ProtocolException('Invalid download init response');
    }
    final initPayload = initResponse.payload;
    if (initPayload.length < 3 ||
        initPayload[0] != 0x75 ||
        initPayload[1] != 0x10) {
      throw ProtocolException('Unexpected download init response');
    }

    // ── Blocks ──
    final buffer = BytesBuilder(copy: false);
    final lreBuffer = BytesBuilder(copy: false);
    var done = false;
    var blockNum = 1;
    var nbytes = 0;

    while (nbytes < size && !done) {
      final blockRequest = Uint8List.fromList([0x36, blockNum]);
      final blockResponse = await _transfer(blockRequest);

      if (!blockResponse.isValid) {
        throw ProtocolException('Invalid download block response');
      }

      final blockPayload = blockResponse.payload;
      if (blockPayload.length < 2 ||
          blockPayload[0] != 0x76 ||
          blockPayload[1] != blockNum) {
        throw ProtocolException(
            'Unexpected download block response: expected block $blockNum');
      }

      final blockData = blockPayload.sublist(2);
      nbytes += blockData.length;

      if (compressed) {
        final lreResult = lreDecode(Uint8List.fromList(blockData));
        lreBuffer.add(lreResult.data);
        if (lreResult.isFinal) {
          done = true;
        }
      } else {
        buffer.add(blockData);
      }

      blockNum = (blockNum + 1) & 0xFF;
    }

    // ── Quit ──
    final quitResponse = await _transfer(Uint8List.fromList([0x37]));
    if (!quitResponse.isValid) {
      throw ProtocolException('Invalid download quit response');
    }
    final quitPayload = quitResponse.payload;
    if (quitPayload.length < 2 ||
        quitPayload[0] != 0x77 ||
        quitPayload[1] != 0x00) {
      throw ProtocolException('Unexpected download quit response');
    }

    // ── Finalize ──
    if (compressed) {
      final data = lreBuffer.toBytes();
      xorDecode(data);
      return data;
    } else {
      return buffer.toBytes();
    }
  }
}

/// Exception thrown by protocol operations.
class ProtocolException implements Exception {
  final String message;
  ProtocolException(this.message);

  @override
  String toString() => 'ProtocolException: $message';
}
