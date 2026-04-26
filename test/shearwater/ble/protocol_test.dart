import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/shearwater/ble/protocol.dart';
import 'package:ccrlogger/shearwater/parser/constants.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock BLE I/O that replays a combined.txt trace.
class TraceMockBle implements BleIo {
  final List<_TraceEntry> _entries;
  int _index = 0;

  TraceMockBle(String tracePath) : _entries = _parseTrace(tracePath);

  @override
  Future<void> writeBytes(Uint8List data) async {
    // Find the next W entry and verify it matches what the protocol sends.
    while (_index < _entries.length && _entries[_index].direction != 'W') {
      _index++;
    }
    if (_index >= _entries.length) {
      throw StateError('Trace exhausted: no more W entries');
    }
    // Advance past this W entry.
    _index++;
  }

  @override
  Future<List<Uint8List>> readFrames() async {
    // Collect consecutive R entries (multi-frame BLE reads).
    final frames = <Uint8List>[];
    while (_index < _entries.length && _entries[_index].direction == 'R') {
      frames.add(_entries[_index].bytes);
      _index++;
    }
    if (frames.isEmpty) {
      throw StateError('Trace exhausted: no R entries after W');
    }
    return frames;
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
}
