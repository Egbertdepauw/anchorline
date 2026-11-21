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

  group('a dive the computer refuses (#261)', () {
    /// The recorded trace with [refuseInits] / [disconnectDuring], read up
    /// to the manifest, and the three newest dives (716-718) downloaded.
    /// The stream's events and its error, if any.
    Future<({List<DownloadEvent> events, Object? error, TraceMockBle ble})>
        downloadThree(
            {int? refuse716,
            ({int address, int afterBlocks})? disconnectDuring}) async {
      // Filled in below, once the manifest gives dive 716's address.
      final ble = TraceMockBle('test/fixtures/raw/subsurface2.combined.txt',
          refuseInits: <int, int>{}, disconnectDuring: disconnectDuring);
      final t = ShearwaterBleTransport(divePipelineWindow: 1)
        ..connectWithIo(ble);
      final info = await t.readDeviceInfo();
      final three = (await t.readManifest()).take(3).toList();
      if (refuse716 != null) {
        final e716 = three.firstWhere((e) => e.diveNumber == 716);
        ble.refuseInits[info.baseAddress + e716.address] = refuse716;
      }
      final events = <DownloadEvent>[];
      Object? error;
      await t.downloadDives(three).handleError((Object e) => error = e)
          .forEach(events.add);
      return (events: events, error: error, ble: ble);
    }

    List<int> downloaded(List<DownloadEvent> events) => [
          for (final e in events)
            if (e is DownloadedDive) e.manifest.diveNumber,
        ];

    test('a refusal of the first of three dives skips it and imports the rest',
        () async {
      final r = await downloadThree(refuse716: 0x31);

      expect(r.error, isNull);
      expect(r.ble.refusedInits, hasLength(1));
      final refused = r.events.whereType<DownloadRefusedDive>().toList();
      expect([for (final e in refused) e.manifest.diveNumber], [716]);
      expect(refused.single.errorCode, 0x31);
      // The refusal comes in download order, before the next dive starts.
      final order = [
        for (final e in r.events)
          if (e is DownloadRefusedDive)
            'refused ${e.manifest.diveNumber}'
          else if (e is DownloadedDive)
            'dive ${e.manifest.diveNumber}',
      ];
      expect(order, ['refused 716', 'dive 717', 'dive 718']);
      // No Quit after the refused Init (the replay would not match it), and
      // dives 717 and 718 are still their own bytes.
      expect(downloaded(r.events), [717, 718]);
      for (final d in r.events.whereType<DownloadedDive>()) {
        final fixture = File(
                'test/fixtures/dives/dive_${d.manifest.diveNumber}.bin')
            .readAsBytesSync();
        expect(d.data, equals(fixture),
            reason: 'dive ${d.manifest.diveNumber}');
      }
    });

    test('an init NAK with a sequence error still fails the import',
        () async {
      final r = await downloadThree(refuse716: 0x24);

      expect(r.error, isA<DownloadInitNakException>());
      expect(r.events.whereType<DownloadRefusedDive>(), isEmpty);
      expect(downloaded(r.events), isEmpty);
    });

    test('a disconnect mid-dive still fails the import', () async {
      // Dive 717's address, from the manifest of a separate replay.
      final probe = TraceMockBle('test/fixtures/raw/subsurface2.combined.txt');
      final pt = ShearwaterBleTransport(divePipelineWindow: 1)
        ..connectWithIo(probe);
      final info = await pt.readDeviceInfo();
      final e717 =
          (await pt.readManifest()).firstWhere((e) => e.diveNumber == 717);

      final r = await downloadThree(disconnectDuring: (
        address: info.baseAddress + e717.address,
        afterBlocks: 2,
      ));

      expect(r.error, isA<StateError>());
      expect(downloaded(r.events), [716]);
      expect(r.events.whereType<DownloadRefusedDive>(), isEmpty);
    });
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
