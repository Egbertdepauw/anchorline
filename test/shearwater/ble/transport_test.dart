import 'dart:io';

import 'package:ccrlogger/shearwater/ble/protocol.dart';
import 'package:ccrlogger/shearwater/ble/shearwater_ble_transport.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:flutter_test/flutter_test.dart';

// Re-use the TraceMockBle from protocol_test.
import 'protocol_test.dart';

void main() {
  late ShearwaterBleTransport transport;

  setUp(() {
    // The trace has no RDBI 0x8060, so this replay NAKs it and the model
    // comes from the hardware ID table; the group at the end covers the
    // model number itself.
    final mockBle =
        TraceMockBle('test/fixtures/raw/subsurface2.combined.txt');
    // The recorded trace is strictly sequential — replay it that way.
    transport = ShearwaterBleTransport(divePipelineWindow: 1);
    transport.connectWithIo(mockBle);
  });

  test('readDeviceInfo returns correct device info', () async {
    final info = await transport.readDeviceInfo();

    expect(info.serial, equals('B89641E4'));
    expect(info.firmware, equals('V103 DiveCAN'));
    expect(info.hardwareId, equals(0xB407));
    expect(info.model, equals(ShearwaterModel.petrel3));
    expect(info.baseAddress, equals(0x80000000));
  });

  test('readManifest returns valid dive entries', () async {
    await transport.readDeviceInfo();
    final manifest = await transport.readManifest();

    // Our trace has 5 manifest pages × 48 slots = 240 max
    // 230 valid entries across dives #489-#718
    expect(manifest.length, equals(230));
    expect(manifest.first.diveNumber, equals(718));
    expect(manifest.last.diveNumber, equals(489));
  });

  test('full import: readDeviceInfo + readManifest + downloadDive + parse',
      () async {
    final info = await transport.readDeviceInfo();
    final manifest = await transport.readManifest();

    // Download just the first dive from the trace.
    // The trace has 8 dive downloads after the manifest.
    final firstEntry = manifest.first; // Dive #718
    expect(firstEntry.diveNumber, equals(718));

    // Download via stream (take first). The stream now interleaves
    // DownloadProgressEvent with DownloadedDive; filter to dives.
    final events = await transport.downloadDives([firstEntry]).toList();
    final dives = events.whereType<DownloadedDive>().toList();
    expect(dives, hasLength(1));

    final downloaded = dives.first;
    expect(downloaded.manifest.diveNumber, equals(718));

    // Parse the downloaded blob.
    final parser = ShearwaterDiveParser(model: info.model);
    final dive = parser.parse(downloaded.data);

    expect(dive.samples, isNotEmpty);
    expect(dive.header.startTimestamp, equals(0x69E4A356));
    expect(dive.header.isPnf, isTrue);
    expect(dive.footer.diveTimeSeconds, greaterThan(0));

    // Verify byte-identical to fixture.
    final fixture = File('test/fixtures/dives/dive_718.bin').readAsBytesSync();
    expect(downloaded.data, equals(fixture));
  });

  group('model number (RDBI 0x8060)', () {
    /// The recorded trace, with RDBI 0x8060 (which it doesn't have)
    /// answered by [modelResponse], or NAKed when that's null.
    (ShearwaterBleTransport, TraceMockBle) replay({List<int>? modelResponse}) {
      final ble = TraceMockBle('test/fixtures/raw/subsurface2.combined.txt',
          rdbiResponses: {0x8060: ?modelResponse});
      final t = ShearwaterBleTransport(divePipelineWindow: 1)
        ..connectWithIo(ble);
      return (t, ble);
    }

    test('reads the model number', () async {
      final (t, ble) = replay(modelResponse: [10]); // Petrel 3
      final info = await t.readDeviceInfo();

      expect(ble.unrecordedRdbiIds, equals([0x8060]));
      expect(info.model, equals(ShearwaterModel.petrel3));
      expect(info.hardwareId, equals(0xB407));
      expect(info.baseAddress, equals(0x80000000));
      // The replay is still in step with the recording.
      expect(await t.readManifest(), hasLength(230));
    });

    test('takes the model number over the hardware ID table', () async {
      // Hardware ID 0xB407 maps to a Petrel 3; the number says Perdix 2.
      final (t, _) = replay(modelResponse: [11]);
      final info = await t.readDeviceInfo();

      expect(info.model, equals(ShearwaterModel.perdix2));
      expect(info.hardwareId, equals(0xB407));
    });

    test('an unknown model number gives unknown, not the table', () async {
      final (t, _) = replay(modelResponse: [99]);
      final info = await t.readDeviceInfo();

      expect(info.model, equals(ShearwaterModel.unknown));
      expect(info.hardwareId, equals(0xB407));
    });

    test('falls back to the hardware ID table when 0x8060 is NAKed',
        () async {
      final (t, ble) = replay();
      final info = await t.readDeviceInfo();

      expect(ble.unrecordedRdbiIds, equals([0x8060]));
      expect(info.model, equals(ShearwaterModel.petrel3));
      expect(info.hardwareId, equals(0xB407));
    });

    test('rejects a model number that is not one byte', () async {
      final (t, _) = replay(modelResponse: [0x00, 0x0A]);

      await expectLater(
          t.readDeviceInfo(), throwsA(isA<ProtocolException>()));
    });
  });
}
