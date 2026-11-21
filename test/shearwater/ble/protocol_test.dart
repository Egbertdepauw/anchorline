import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/shearwater/ble/protocol.dart';
import 'package:ccrlogger/shearwater/ble/slip_codec.dart';
import 'package:subsurface_core/shearwater/parser/constants.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock BLE I/O that replays a combined.txt trace.
///
/// Every request must match the recording. Download Inits (0x35) are
/// answered by address, the way the device answers them: an Init may come
/// wherever the recording has one, and the replay jumps to the next
/// recorded download of the requested address, whose Init must match the
/// request byte for byte. A test that asks for dives in another order than
/// the recording (the transport asks in ascending address order, the trace
/// has them newest first) still gets each dive's own bytes, so a mispairing
/// of entry and blob shows up instead of being replayed into place. Every
/// other request must be the next one in the recording, with one
/// exception: an RDBI request the recording doesn't have at that point
/// (the trace predates RDBI 0x8060) is answered from [rdbiResponses], or
/// with a NAK when the identifier isn't in there. [rewriteResponse] can
/// replace recorded responses, to replay the trace with variations the
/// recorded device never sent. [refuseInits] answers the Init of an address
/// with a NAK instead of its recording, and [disconnectDuring] drops the
/// link part-way through the download of an address.
class TraceMockBle implements BleIo {
  final List<_TraceEntry> _entries;

  /// Trace indices of the recorded Init writes, per requested address, in
  /// recorded order (the manifest address is downloaded once per page).
  final Map<int, List<int>> _initsByAddress;

  /// How many recorded downloads of each address have been replayed.
  final Map<int, int> _initsReplayed = {};

  int _index = 0;

  /// Response data (after the `62 id_hi id_lo` header) for RDBI
  /// identifiers the recording doesn't have.
  final Map<int, List<int>> rdbiResponses;

  /// Called with each recorded response payload (after the 4-byte packet
  /// header); a non-null result is sent instead.
  final List<int>? Function(Uint8List payload)? rewriteResponse;

  /// RDBI identifiers requested that the recording doesn't have, in order.
  final List<int> unrecordedRdbiIds = [];

  /// Payload of a response to an unrecorded request, sent on the next read.
  List<int>? _unrecordedResponse;

  /// Download addresses whose Init is answered with `7F 35 <NRC>`, the
  /// NRC per address. The replay stays where it was, so any request but
  /// another Init after the NAK fails to match the recording.
  final Map<int, int> refuseInits;

  /// Drops the link once [afterBlocks] block responses of the download of
  /// [address] have been read: the next read throws what
  /// `FlutterBluePlusBleIo` throws when the link goes.
  final ({int address, int afterBlocks})? disconnectDuring;

  /// Addresses whose Init was answered with a NAK from [refuseInits].
  final List<int> refusedInits = [];

  /// The address of the latest Init, and reads since it (its response
  /// included).
  int? _initAddressSent;
  int _readsSinceInit = 0;

  TraceMockBle(String tracePath,
      {Map<int, List<int>> rdbiResponses = const {},
      List<int>? Function(Uint8List payload)? rewriteResponse,
      Map<int, int> refuseInits = const {},
      ({int address, int afterBlocks})? disconnectDuring})
      : this._(_parseTrace(tracePath), rdbiResponses, rewriteResponse,
            refuseInits, disconnectDuring);

  TraceMockBle._(this._entries, this.rdbiResponses, this.rewriteResponse,
      this.refuseInits, this.disconnectDuring)
      : _initsByAddress = _indexInits(_entries);

  @override
  Future<void> writeBytes(Uint8List data) async {
    // All requests in this protocol fit in one BLE frame.
    final request = _payload([data]);

    // Find the next W entry and verify it matches what the protocol sends.
    var next = _index;
    while (next < _entries.length && _entries[next].direction != 'W') {
      next++;
    }

    final address = _initAddress(data);
    if (address != null) {
      _initAddressSent = address;
      _readsSinceInit = 0;
      final nrc = refuseInits[address];
      if (nrc != null) {
        refusedInits.add(address);
        _unrecordedResponse = [0x7F, 0x35, nrc];
        return;
      }
      if (next < _entries.length &&
          _initAddress(_entries[next].bytes) == null) {
        throw StateError('Download Init ${_hexBytes(request)} where the '
            'recording has ${_hexBytes(_payload([_entries[next].bytes]))}');
      }
      final recorded = _initsByAddress[address] ?? const <int>[];
      final replayed = _initsReplayed[address] ?? 0;
      if (replayed >= recorded.length) {
        throw StateError('Trace has no further download of address '
            '0x${address.toRadixString(16)}');
      }
      final init = recorded[replayed];
      final recordedInit = _payload([_entries[init].bytes]);
      if (!_sameBytes(recordedInit, request)) {
        throw StateError('Request ${_hexBytes(request)} does not match the '
            'recorded ${_hexBytes(recordedInit)}');
      }
      _initsReplayed[address] = replayed + 1;
      // Continue right after that Init, with its recorded response.
      _index = init + 1;
      return;
    }

    if (next < _entries.length &&
        _sameBytes(_payload([_entries[next].bytes]), request)) {
      // Advance past this W entry.
      _index = next + 1;
      return;
    }

    if (request.length == 3 && request[0] == 0x22) {
      final id = (request[1] << 8) | request[2];
      unrecordedRdbiIds.add(id);
      final response = rdbiResponses[id];
      // A NAK with NRC 0x31 (requestOutOfRange), what a UDS device sends
      // for an identifier it doesn't support.
      _unrecordedResponse = response == null
          ? [0x7F, 0x22, 0x31]
          : [0x62, request[1], request[2], ...response];
      return;
    }

    if (next >= _entries.length) {
      throw StateError('Trace exhausted: no more W entries');
    }
    throw StateError('Request ${_hexBytes(request)} does not match the '
        'recorded ${_hexBytes(_payload([_entries[next].bytes]))}');
  }

  @override
  Future<List<Uint8List>> readFrames() async {
    _readsSinceInit++;
    final drop = disconnectDuring;
    if (drop != null &&
        _initAddressSent == drop.address &&
        _readsSinceInit > 1 + drop.afterBlocks) {
      throw StateError('Disconnected');
    }
    final unrecorded = _unrecordedResponse;
    if (unrecorded != null) {
      _unrecordedResponse = null;
      return _frames(unrecorded);
    }

    // Collect consecutive R entries (multi-frame BLE reads).
    final frames = <Uint8List>[];
    while (_index < _entries.length && _entries[_index].direction == 'R') {
      frames.add(_entries[_index].bytes);
      _index++;
    }
    if (frames.isEmpty) {
      throw StateError('Trace exhausted: no R entries after W');
    }
    final replacement = rewriteResponse?.call(_payload(frames));
    return replacement == null ? frames : _frames(replacement);
  }

  /// The command payload of a packet sent as BLE [frames], without the
  /// 4-byte packet header.
  static Uint8List _payload(List<Uint8List> frames) {
    final packet = BleSlipCodec.decode(frames);
    return packet.length < 4 ? packet : Uint8List.sublistView(packet, 4);
  }

  /// BLE frames for a response packet carrying [payload].
  static List<Uint8List> _frames(List<int> payload) =>
      BleSlipCodec.encode(Uint8List.fromList(
          [0x01, 0xFF, payload.length + 1, 0x00, ...payload]));

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _hexBytes(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  @override
  void drainPendingFrames() {
    // No-op: the trace mock has no concurrent producer, so there are
    // never "stale" frames to drop — each readFrames() consumes its
    // exact lockstep R entries.
  }

  /// The flash address of the download Init (0x35) one BLE frame carries,
  /// or null for any other command.
  static int? _initAddress(Uint8List frame) {
    // Inits fit in one frame: [frames=1, index=0, SLIP data...].
    if (frame.length < 2 || frame[0] != 1) return null;
    final packet = BleSlipCodec.decode([frame]);
    // [0xFF, 0x01, len, 0x00, 0x35, compression, 0x34, address (4), size (3)]
    if (packet.length < 11 || packet[4] != 0x35) return null;
    return (packet[7] << 24) | (packet[8] << 16) | (packet[9] << 8) | packet[10];
  }

  static Map<int, List<int>> _indexInits(List<_TraceEntry> entries) {
    final inits = <int, List<int>>{};
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].direction != 'W') continue;
      final address = _initAddress(entries[i].bytes);
      if (address != null) (inits[address] ??= []).add(i);
    }
    return inits;
  }

  static List<_TraceEntry> _parseTrace(String path) {
    final entries = <_TraceEntry>[];
    for (final line in File(path).readAsLinesSync()) {
      final match =
          RegExp(r'^([WR]) \(\d+ bytes\): (.+)$').firstMatch(line.trim());
      if (match == null) continue;
      final direction = match.group(1)!;
      final bytes = Uint8List.fromList(
          match.group(2)!.split(' ').map((h) => int.parse(h, radix: 16)).toList());
      entries.add(_TraceEntry(direction, bytes));
    }
    return entries;
  }
}

class _TraceEntry {
  final String direction;
  final Uint8List bytes;
  _TraceEntry(this.direction, this.bytes);
}

void main() {
  late TraceMockBle mockBle;
  late ShearwaterProtocol protocol;

  setUp(() {
    mockBle = TraceMockBle('test/fixtures/raw/subsurface2.combined.txt');
    protocol = ShearwaterProtocol(mockBle);
  });

  group('RDBI (Read Data By Identifier)', () {
    test('reads serial number', () async {
      final data = await protocol.rdbi(idSerial);
      // Serial "B89641E4" as ASCII bytes
      expect(String.fromCharCodes(data), equals('B89641E4'));
    });

    test('reads firmware version', () async {
      // Skip serial RDBI
      await protocol.rdbi(idSerial);
      final data = await protocol.rdbi(idFirmware);
      expect(String.fromCharCodes(data), equals('V103 DiveCAN'));
    });

    test('reads hardware type', () async {
      await protocol.rdbi(idSerial);
      await protocol.rdbi(idFirmware);
      final data = await protocol.rdbi(idHardware);
      expect(data.length, equals(2));
      final hw = (data[0] << 8) | data[1];
      expect(hw, equals(0xB407)); // Petrel 3
      expect(modelFromHardware(hw), equals(ShearwaterModel.petrel3));
    });

    test('reads logupload config', () async {
      await protocol.rdbi(idSerial);
      await protocol.rdbi(idFirmware);
      await protocol.rdbi(idHardware);
      final data = await protocol.rdbi(idLogUpload);
      // Base address at bytes 1-4
      final baseAddr =
          (data[1] << 24) | (data[2] << 16) | (data[3] << 8) | data[4];
      expect(baseAddr, equals(0x80000000)); // PNF format
    });
  });

  group('download', () {
    test('downloads manifest (uncompressed)', () async {
      // Skip the 4 RDBI queries
      await protocol.rdbi(idSerial);
      await protocol.rdbi(idFirmware);
      await protocol.rdbi(idHardware);
      await protocol.rdbi(idLogUpload);

      // Download manifest
      final data = await protocol.download(
        address: manifestAddr,
        size: manifestSize,
        compressed: false,
      );

      expect(data.length, equals(manifestSize));
      // First record should be valid (0xA5C4)
      expect((data[0] << 8) | data[1], equals(manifestHeaderValid));
    });

    test('downloads and decompresses a dive (compressed)', () async {
      // Skip 4 RDBI + 5 manifest pages to get to the first dive download.
      // Each manifest page = init + blocks + quit.
      await protocol.rdbi(idSerial);
      await protocol.rdbi(idFirmware);
      await protocol.rdbi(idHardware);
      await protocol.rdbi(idLogUpload);

      for (var i = 0; i < 5; i++) {
        await protocol.download(
          address: manifestAddr,
          size: manifestSize,
          compressed: false,
        );
      }

      // Now download dive 718 (first dive in trace, compressed).
      // Address: base 0x80000000 + offset 0x008A6AC0
      final diveData = await protocol.download(
        address: 0x808A6AC0,
        size: 0xFFFFFF, // DIVE_SIZE
        compressed: true,
      );

      // Compare against fixture extracted by tool/extract_fixtures.dart
      final fixture = File('test/fixtures/dives/dive_718.bin').readAsBytesSync();
      expect(diveData.length, equals(fixture.length));
      expect(diveData, equals(fixture));
    });
  });

  group('parseDownloadInitResponse', () {
    int parse(List<int> payload) =>
        ShearwaterProtocol.parseDownloadInitResponse(
            Uint8List.fromList(payload));

    test('reads the 1-byte field the Petrel 3 sends', () {
      // As recorded: manifest and dive init responses.
      expect(parse([0x75, 0x10, 0x82]), equals(130));
      expect(parse([0x75, 0x10, 0x92]), equals(146));
    });

    test('reads longer fields, big-endian', () {
      expect(parse([0x75, 0x20, 0x00, 0x92]), equals(146));
      expect(parse([0x75, 0x30, 0x00, 0x00, 0xFE]), equals(254));
      expect(parse([0x75, 0x40, 0x00, 0x00, 0x00, 0x92]), equals(146));
    });

    test('takes the field length from the upper nibble only', () {
      expect(parse([0x75, 0x1F, 0x92]), equals(146));
    });

    test('rejects a response that is not an init response', () {
      expect(() => parse([0x7F, 0x35, 0x31]),
          throwsA(isA<ProtocolException>()));
      expect(() => parse([0x75]), throwsA(isA<ProtocolException>()));
    });

    test('rejects a field longer than 4 bytes', () {
      expect(() => parse([0x75, 0x50, 0x00, 0x00, 0x00, 0x00, 0x92]),
          throwsA(isA<ProtocolException>()));
    });

    test('rejects a truncated field', () {
      expect(() => parse([0x75, 0x20, 0x00]),
          throwsA(isA<ProtocolException>()));
      expect(() => parse([0x75, 0x10]), throwsA(isA<ProtocolException>()));
    });

    test('rejects packets larger than the protocol carries', () {
      expect(parse([0x75, 0x10, maxPacketSizeV1]), equals(254));
      expect(() => parse([0x75, 0x20, 0x00, 0xFF]),
          throwsA(isA<ProtocolException>()));
      // The Perdix 3's largest dive packet, per libdivecomputer.
      expect(() => parse([0x75, 0x20, 0x09, 0x02]),
          throwsA(isA<ProtocolException>()));
    });
  });

  group('download with a multi-byte init response field', () {
    /// Replays the trace with every init response's 1-byte max-packet
    /// field (`75 10 nn`) rewritten as [field].
    TraceMockBle withInitField(List<int> Function(int maxPacket) field) =>
        TraceMockBle('test/fixtures/raw/subsurface2.combined.txt',
            rewriteResponse: (payload) =>
                payload.length == 3 && payload[0] == 0x75 && payload[1] == 0x10
                    ? [0x75, ...field(payload[2])]
                    : null);

    Future<void> readDeviceInfoRdbis(ShearwaterProtocol p) async {
      await p.rdbi(idSerial);
      await p.rdbi(idFirmware);
      await p.rdbi(idHardware);
      await p.rdbi(idLogUpload);
    }

    test('downloads the manifest and dive 718 with a 2-byte field',
        () async {
      final p = ShearwaterProtocol(withInitField((n) => [0x20, 0x00, n]));
      await readDeviceInfoRdbis(p);

      for (var i = 0; i < 5; i++) {
        final manifest = await p.download(
          address: manifestAddr,
          size: manifestSize,
          compressed: false,
        );
        expect(manifest.length, equals(manifestSize));
      }

      final diveData = await p.download(
        address: 0x808A6AC0,
        size: 0xFFFFFF,
        compressed: true,
      );
      final fixture = File('test/fixtures/dives/dive_718.bin').readAsBytesSync();
      expect(diveData, equals(fixture));
    });

    test('stops when the device announces packets above 254 bytes',
        () async {
      final p = ShearwaterProtocol(withInitField((_) => [0x20, 0x09, 0x02]));
      await readDeviceInfoRdbis(p);

      await expectLater(
        p.download(
          address: manifestAddr,
          size: manifestSize,
          compressed: false,
        ),
        throwsA(isA<ProtocolException>().having(
            (e) => e.message, 'message', contains('max packet 2306'))),
      );
    });
  });

  group('download init NAK', () {
    Future<ShearwaterProtocol> afterManifest(TraceMockBle ble) async {
      final p = ShearwaterProtocol(ble);
      await p.rdbi(idSerial);
      await p.rdbi(idFirmware);
      await p.rdbi(idHardware);
      await p.rdbi(idLogUpload);
      for (var i = 0; i < 5; i++) {
        await p.download(
            address: manifestAddr, size: manifestSize, compressed: false);
      }
      return p;
    }

    test('throws DownloadInitNakException with the NRC', () async {
      final ble = TraceMockBle('test/fixtures/raw/subsurface2.combined.txt',
          refuseInits: {0x808A6AC0: 0x31});
      final p = await afterManifest(ble);

      await expectLater(
        p.download(address: 0x808A6AC0, size: 0xFFFFFF, compressed: true),
        throwsA(isA<DownloadInitNakException>()
            .having((e) => e.errorCode, 'errorCode', 0x31)
            .having((e) => e.refusesRequest, 'refusesRequest', isTrue)),
      );
      expect(ble.refusedInits, equals([0x808A6AC0]));
    });

    test('a sequence error or a pending response is not a refusal', () {
      // 0x24: the device thinks a transfer is still open. 0x78: it will
      // answer later. 0x11 / 0x7F: it does not take uploads at all now.
      for (final nrc in [0x11, 0x24, 0x78, 0x7F]) {
        expect(DownloadInitNakException(nrc).refusesRequest, isFalse,
            reason: 'NRC 0x${nrc.toRadixString(16)}');
      }
      for (final nrc in [0x13, 0x22, 0x31, 0x70]) {
        expect(DownloadInitNakException(nrc).refusesRequest, isTrue,
            reason: 'NRC 0x${nrc.toRadixString(16)}');
      }
    });

    test('a NAK for another service is not an init NAK', () async {
      // A late `7F 36 24` from a previous download, read as the answer
      // to this Init, says nothing about this dive.
      final ble = TraceMockBle('test/fixtures/raw/subsurface2.combined.txt',
          rewriteResponse: (payload) =>
              payload.length == 3 && payload[0] == 0x75 && payload[2] == 0x92
                  ? [0x7F, 0x36, 0x24]
                  : null);
      final p = await afterManifest(ble);

      await expectLater(
        p.download(address: 0x808A6AC0, size: 0xFFFFFF, compressed: true),
        throwsA(isA<ProtocolException>().having(
            (e) => e, 'type', isNot(isA<DownloadInitNakException>()))),
      );
    });
  });

  group('RDBI NAK', () {
    test('throws RdbiNakException for an identifier the device NAKs',
        () async {
      // The recording has no RDBI 0x8060; the replay NAKs it.
      await protocol.rdbi(idSerial);
      await protocol.rdbi(idFirmware);
      await protocol.rdbi(idHardware);
      await expectLater(
        protocol.rdbi(idModel),
        throwsA(isA<RdbiNakException>()
            .having((e) => e.id, 'id', idModel)
            .having((e) => e.errorCode, 'errorCode', 0x31)),
      );
      // The replay carries on with the next recorded request.
      final data = await protocol.rdbi(idLogUpload);
      expect(data[1], equals(0x80));
    });
  });
}
