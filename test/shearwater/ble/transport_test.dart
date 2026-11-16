import 'dart:io';

import 'package:ccrlogger/shearwater/ble/shearwater_ble_transport.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:flutter_test/flutter_test.dart';

// Re-use the TraceMockBle from protocol_test.
import 'protocol_test.dart';

void main() {
  late ShearwaterBleTransport transport;

  setUp(() {
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

  test('each entry is paired with the blob downloaded from its own address',
      () async {
    await transport.readDeviceInfo();
    final manifest = await transport.readManifest();

    // The trace recorded 718 before 717 (manifest order), while the
    // transport asks in ascending address order (717 first). The replay
    // answers by address, so each entry must get its own dive's bytes.
    final events =
        await transport.downloadDives(manifest.take(3).toList()).toList();
    final dives = events.whereType<DownloadedDive>().toList();
    expect([for (final d in dives) d.manifest.diveNumber], [716, 717, 718]);
    for (final d in dives) {
      final fixture = File(
              'test/fixtures/dives/dive_${d.manifest.diveNumber}.bin')
          .readAsBytesSync();
      expect(d.data, equals(fixture), reason: 'dive ${d.manifest.diveNumber}');
    }
  });
}
