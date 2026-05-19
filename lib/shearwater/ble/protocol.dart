/// High-level Shearwater protocol operations over BLE.
///
/// Implements RDBI, WDBI, and the download protocol on top of
/// a [BleIo] abstraction that provides raw BLE read/write.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart';

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
    await _sendRequest(commandPayload);
    return _receiveResponse();
  }

  /// Send a request without waiting for the response. Pairs with
  /// [_receiveResponse] for pipelined operation in [download].
  Future<void> _sendRequest(Uint8List commandPayload) async {
    final requestPacket = Packet.buildRequest(commandPayload);
    final frames = BleSlipCodec.encode(requestPacket);
    final writeStart = DateTime.now();
    for (final frame in frames) {
      await _ble.writeBytes(frame);
    }
    _lastWriteMs = DateTime.now().difference(writeStart).inMilliseconds;
    _lastWriteFrameCount = frames.length;
  }

  /// Receive the next response packet. Pairs with [_sendRequest] for
  /// pipelined operation in [download].
  ///
  /// A 5-second timeout wraps the underlying read. On a healthy link a
  /// block round-trip is ~80 ms — anything over a few hundred ms means
  /// the link has stalled (BLE connection died, Petrel firmware locked up,
  /// or we've over-run the actual end of the dive blob). Without this
  /// timeout the read would hang forever and the import would silently
  /// stall until some upstream timer fired a disconnect.
  Future<ResponsePacket> _receiveResponse() async {
    final readStart = DateTime.now();
    final responseFrames = await _ble.readFrames().timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw ProtocolException(
        'BLE read timed out after 5s — link stalled or end-of-data over-run',
      ),
    );
    _lastReadMs = DateTime.now().difference(readStart).inMilliseconds;
    _lastReadFrameCount = responseFrames.length;
    final decoded = BleSlipCodec.decode(responseFrames);
    return Packet.parseResponse(decoded);
  }

  /// Last `_transfer` timing — exposed so `download()` can print
  /// per-block round-trip breakdown without re-wrapping every protocol
  /// op. Diagnostic only; cleared on each new transfer.
  int _lastWriteMs = 0;
  int _lastReadMs = 0;
  int _lastWriteFrameCount = 0;
  int _lastReadFrameCount = 0;

  int get lastWriteMs => _lastWriteMs;
  int get lastReadMs => _lastReadMs;
  int get lastWriteFrameCount => _lastWriteFrameCount;
  int get lastReadFrameCount => _lastReadFrameCount;

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
  ///
  /// [pipelineWindow] is the number of `0x36` block requests kept in
  /// flight at once. The default of 1 is strictly sequential and matches
  /// the canonical libdc protocol; the trace-replay tests assume this.
  /// Values ≥2 overlap the next request with the current response,
  /// roughly doubling per-dive throughput on slow BLE links if the
  /// Petrel firmware queues incoming commands (which empirically it
  /// appears to do, based on Shearwater's own app being much faster).
  /// If a pipelined response comes back with an unexpected block
  /// number, the operation throws — callers can fall back to window=1.
  Future<Uint8List> download({
    required int address,
    required int size,
    required bool compressed,
    int pipelineWindow = 1,
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
    // For uncompressed downloads (manifest), the device tells us how big
    // the payload is up front via `size`; we just accumulate until full.
    // For compressed downloads (dive blobs), we accumulate the raw 9-bit
    // LRE bit stream into `rawBuffer` and re-decode the entire buffer after
    // each block to look for the `0` end marker. Per-block decode does NOT
    // work because LRE values are 9 bits wide and BLE block boundaries land
    // mid-value — decoding each block from offset 0 reinterprets the bit
    // alignment and either silently produces garbage or trips the end
    // marker by accident on some blocks and not others. Decoding the full
    // accumulated buffer keeps the bit alignment correct and gives us a
    // reliable isFinal signal at the real end of the dive blob.
    final buffer = BytesBuilder(copy: false);
    final rawBuffer = BytesBuilder(copy: false);
    var done = false;
    // Set when the Petrel terminates the download by responding with NAK
    // NRC=0x24. In that case the session is already closed on the device
    // side and sending Quit yields no response — we'd just wait 5 s for
    // the read timeout. Skip Quit when this flag is set.
    var sessionEndedByPeer = false;
    var nextBlockNum = 1; // The next 0x36 block number to send.
    var nbytes = 0;
    final stopwatch = Stopwatch()..start();
    int? firstBlockMs;
    var blocksRead = 0;
    // Per-block round-trip stats for the post-download summary.
    var totalWriteMs = 0;
    var totalReadMs = 0;
    var maxBlockMs = 0;
    var minBlockMs = 1 << 30;

    // Block numbers sent but not yet received. We push to the back when
    // sending a new request and pop from the front when receiving — the
    // expected response order matches the FIFO send order if the Petrel
    // firmware processes requests in order (verified empirically; if it
    // doesn't, the validate-block-number check below will trip).
    final inFlight = <int>[];

    Future<void> sendNextBlock() async {
      await _sendRequest(Uint8List.fromList([0x36, nextBlockNum]));
      inFlight.add(nextBlockNum);
      nextBlockNum = (nextBlockNum + 1) & 0xFF;
    }

    // Prime the pipeline. window=1 sends one request (sequential).
    // window=2 sends two — by the time the first response comes back,
    // the Petrel is already preparing the second.
    for (var w = 0; w < pipelineWindow; w++) {
      if (nbytes >= size) break;
      await sendNextBlock();
    }

    while (inFlight.isNotEmpty) {
      final expectedBlockNum = inFlight.removeAt(0);
      final blockStart = stopwatch.elapsedMilliseconds;
      final blockResponse = await _receiveResponse();
      final blockMs = stopwatch.elapsedMilliseconds - blockStart;
      firstBlockMs ??= blockMs;
      totalWriteMs += _lastWriteMs;
      totalReadMs += _lastReadMs;
      if (blockMs > maxBlockMs) maxBlockMs = blockMs;
      if (blockMs < minBlockMs) minBlockMs = blockMs;
      blocksRead++;
      if (blocksRead <= 3 || blocksRead % 25 == 0) {
        debugPrint('  block $blocksRead: ${blockMs}ms '
            '(read ${_lastReadMs}ms × ${_lastReadFrameCount}f'
            '${pipelineWindow > 1 ? ', pipelined w=$pipelineWindow' : ', write ${_lastWriteMs}ms × ${_lastWriteFrameCount}f'})');
      }

      if (!blockResponse.isValid) {
        throw ProtocolException('Invalid download block response');
      }

      final blockPayload = blockResponse.payload;
      // Three things can be wrong here; surface each distinctly because
      // the diagnostic story is completely different. NAK (0x7F + svc + NRC)
      // = Petrel rejected the request. Wrong opcode = SLIP/framing problem
      // or Petrel sent something unexpected. BSC mismatch = pipelining
      // out-of-order, sequence-counter wrap mismatch, or end-of-data
      // over-run where the Petrel started returning stale data.
      if (blockPayload.length < 2) {
        throw ProtocolException(
            'Download block response too short: ${blockPayload.length} bytes '
            '(blocksRead=$blocksRead, nbytes=$nbytes)');
      }
      if (blockPayload[0] == 0x7F) {
        final svc = blockPayload[1];
        final nrc = blockPayload.length > 2 ? blockPayload[2] : 0xFF;
        // NRC 0x24 (requestSequenceError) after we've received valid data
        // is the Petrel's "no more data for this dive" signal. The
        // manifest's endAddress field is a flash-allocation boundary
        // (next-dive-start or next-sector-start, rounded up), not the
        // exact compressed-end — when we request that many bytes the
        // firmware happily streams up to its internal end-of-dive marker
        // and then NAKs the next request. Treat it as clean EOS so the
        // remaining in-flight responses can drain and we proceed to Quit.
        if (nrc == 0x24 && nbytes > 0) {
          done = true;
          sessionEndedByPeer = true;
          // Petrel has already closed the download session on its side.
          // Pipelined-but-unanswered requests will not be responded to —
          // clear inFlight so we don't sit in _receiveResponse() waiting
          // 5 s for each pending request to time out.
          inFlight.clear();
          break;
        }
        throw ProtocolException(
            'Download NAK from Petrel: service=0x${svc.toRadixString(16).padLeft(2, '0')}, '
            'NRC=0x${nrc.toRadixString(16).padLeft(2, '0')} '
            '(blocksRead=$blocksRead, nbytes=$nbytes, '
            'expectedBlock=$expectedBlockNum, inFlight=[${inFlight.join(",")}])');
      }
      if (blockPayload[0] != 0x76) {
        throw ProtocolException(
            'Download block wrong opcode: 0x${blockPayload[0].toRadixString(16).padLeft(2, '0')} '
            '(expected 0x76, blocksRead=$blocksRead, nbytes=$nbytes, '
            'expectedBlock=$expectedBlockNum)');
      }
      if (blockPayload[1] != expectedBlockNum) {
        throw ProtocolException(
            'Download block sequence mismatch: expected $expectedBlockNum, '
            'got ${blockPayload[1]} '
            '(blocksRead=$blocksRead, nbytes=$nbytes, '
            'inFlight=[${inFlight.join(",")}], pipelineWindow=$pipelineWindow)');
      }

      final blockData = blockPayload.sublist(2);

      // Skip processing once we've already hit the LRE-final marker on
      // a previous iteration — the remaining in-flight blocks were
      // speculatively requested and contain garbage past end-of-data.
      if (!done) {
        nbytes += blockData.length;
        if (compressed) {
          rawBuffer.add(blockData);
          // Decode the full accumulated raw buffer to check for the end
          // marker. Cheap enough — the bit stream is decoded once more
          // in finalize for the actual data, but each per-block pass is
          // O(nbytes) and nbytes stays small (~30-100 KB per dive). The
          // marker only fires at the very end of the on-flash log, not
          // per dive, so for non-newest dives we rely on nbytes >= size
          // instead (size comes from the manifest's per-dive end address).
          final lreResult = lreDecode(rawBuffer.toBytes());
          if (lreResult.isFinal) {
            done = true;
          }
        } else {
          buffer.add(blockData);
        }
      }

      // Top up the pipeline. After 'done', let it drain — the in-flight
      // requests were already sent and the Petrel will respond to them
      // regardless; we just discard the data above.
      if (!done && nbytes < size) {
        await sendNextBlock();
      }
    }

    // ── Quit ──
    // When the Petrel terminated the session via NAK NRC=0x24, it has
    // already cleaned up internally and will NOT respond to 0x37 — so
    // sending Quit would just block on the read timeout. Skip it in that
    // case; the next download() call's Init (0x35) starts a fresh
    // session regardless.
    if (!sessionEndedByPeer) {
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
    }

    final totalMs = stopwatch.elapsedMilliseconds;
    final kbps = totalMs > 0
        ? (nbytes / totalMs * 1000 / 1024).toStringAsFixed(1)
        : 'inf';
    final avgWriteMs =
        blocksRead > 0 ? (totalWriteMs / blocksRead).toStringAsFixed(1) : '0';
    final avgReadMs =
        blocksRead > 0 ? (totalReadMs / blocksRead).toStringAsFixed(1) : '0';
    debugPrint('download(addr=0x${address.toRadixString(16)}) '
        '$blocksRead blocks, ${nbytes}B, ${totalMs}ms '
        '($kbps KB/s, first block ${firstBlockMs ?? 0}ms, '
        'block min/max ${minBlockMs == 1 << 30 ? 0 : minBlockMs}/${maxBlockMs}ms, '
        'avg write ${avgWriteMs}ms / read ${avgReadMs}ms)');

    // ── Finalize ──
    if (compressed) {
      // Decode the raw bit stream one final time to get the actual data.
      // The per-block decodes above only checked isFinal; we deliberately
      // discarded their output because re-deriving the full data from the
      // raw buffer here is simpler than tracking a partial-decode cursor.
      final data = lreDecode(rawBuffer.toBytes()).data;
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
