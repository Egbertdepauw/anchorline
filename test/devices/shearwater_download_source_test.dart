import 'dart:typed_data';

import 'package:ccrlogger/devices/dive_download_source.dart';
import 'package:ccrlogger/devices/shearwater/shearwater_download_source.dart';
import 'package:ccrlogger/shearwater/ble/mock_ble_transport.dart';
import 'package:ccrlogger/shearwater/ble/shearwater_ble_transport.dart';
import 'package:ccrlogger/shearwater/ble/shearwater_link.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/manifest_parser.dart';
import 'package:ccrlogger/shearwater/parser/parser_version.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subsurface_core/data/models/dive.dart' show generateDiveId;
import 'package:subsurface_core/data/sample_codec/sample_codec.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';

import '../shearwater/ble/protocol_test.dart';

ShearwaterBleTransport _traceTransport() {
  final mockBle = TraceMockBle('test/fixtures/raw/subsurface2.combined.txt');
  // The recorded trace is strictly sequential, replay it that way.
  return ShearwaterBleTransport(divePipelineWindow: 1)
    ..connectWithIo(mockBle);
}

/// A link that emits a fixed list of events, for the failure test.
class _FakeLink implements ShearwaterLink {
  final List<DownloadEvent> events;
  _FakeLink(this.events);

  @override
  Future<DeviceInfo> readDeviceInfo() async => DeviceInfo(
        serial: 'B89641E4',
        firmware: 'V103 DiveCAN',
        hardwareId: 0xB407,
        model: ShearwaterModel.petrel3,
        baseAddress: 0x80000000,
      );

  @override
  Future<List<ManifestEntry>> readManifest({Uint8List? lastFingerprint}) async =>
      [for (final e in events) if (e is DownloadedDive) e.manifest];

  @override
  Stream<DownloadEvent> downloadDives(List<ManifestEntry> entries) =>
      Stream.fromIterable(events);

  @override
  Future<void> disconnect() async {}
}

ManifestEntry _entry(int n, int start) => ManifestEntry(
      header: 0xA5C4,
      diveNumber: n,
      fingerprint: Uint8List.fromList([0, 0, 0, n & 0xFF]),
      startTimestamp: start,
      endTimestamp: start + 3600,
      address: 0,
      endAddress: 0x10000,
    );

void main() {
  test('identity comes from the device info', () async {
    final source = await ShearwaterDownloadSource.open(_traceTransport());
    final id = source.identity;
    expect(id.vendor, 'Shearwater');
    expect(id.product, 'Petrel 3');
    expect(id.serial, 0xB89641E4);
    expect(id.importStateKey, 'B89641E4');
    expect(id.modelLabel, 'petrel3');
    expect(id.serialLabel, 'B89641E4');
    expect(id.firmwareLabel, 'V103 DiveCAN');
    expect(id.dcModel, ShearwaterModel.petrel3);
    expect(id.computerModel, 0xB407);
    expect(id.firmware, 103);
    expect(source.canListDives, isTrue);
  });

  test('listDives returns the manifest, each with the computed dive id',
      () async {
    final t = _traceTransport();
    final source = await ShearwaterDownloadSource.open(t);
    final listings = await source.listDives();
    expect(listings.length, 230);
    expect(listings.first.diveNumber, 718);
    for (final l in listings) {
      expect(l.diveId,
          generateDiveId(0xB89641E4, l.diveNumber, l.startTimestamp));
    }
  });

  test('download gives the same dives as parsing the transport\'s blobs directly',
      () async {
    // Reference: parse the blobs straight off a second transport.
    final ref = _traceTransport();
    final info = await ref.readDeviceInfo();
    final refManifest = await ref.readManifest();
    final refEntries = refManifest.take(2).toList();
    final refDives = (await ref.downloadDives(refEntries).toList())
        .whereType<DownloadedDive>()
        .toList();
    expect(refDives, hasLength(2));

    final source = await ShearwaterDownloadSource.open(_traceTransport());
    final listings = await source.listDives();
    final events =
        await source.download(selection: listings.take(2).toList()).toList();
    final dives = events.whereType<DiveSourceDive>().toList();
    expect(dives, hasLength(2));
    expect(events.whereType<DiveSourceProgress>(), isNotEmpty);

    final parser = ShearwaterDiveParser(model: info.model);
    for (var i = 0; i < 2; i++) {
      final expected = DiveConverter.convert(
        parsed: parser.parse(refDives[i].data),
        dcSerial: int.parse(info.serial, radix: 16),
        dcDiveNumber: refDives[i].manifest.diveNumber,
        dcModel: info.model,
      );
      final got = dives[i];
      expect(got.rawBlob, refDives[i].data);
      expect(got.parserVersion, kShearwaterParserVersion);
      expect(got.fingerprint, refDives[i].manifest.fingerprint);
      expect(got.listing!.diveNumber, refDives[i].manifest.diveNumber);
      final a = got.converted.dive;
      final b = expected.dive;
      expect(a.id, b.id);
      expect(a.dcSerial, b.dcSerial);
      expect(a.dcDiveNumber, b.dcDiveNumber);
      expect(a.startTime, b.startTime);
      expect(a.endTime, b.endTime);
      expect(a.duration, b.duration);
      expect(a.maxDepthMeters, b.maxDepthMeters);
      expect(a.diveMode, b.diveMode);
      expect(a.gfLow, b.gfLow);
      expect(a.gfHigh, b.gfHigh);
      final ea = SampleCodec.encode(got.converted.samples);
      final eb = SampleCodec.encode(expected.samples);
      expect(ea.keys, eb.keys);
      for (final k in ea.keys) {
        expect(ea[k], eb[k], reason: 'column $k');
      }
    }
  });

  test('a dive that fails to parse yields DiveSourceDiveFailed and the next dive still arrives',
      () async {
    final ref = _traceTransport();
    await ref.readDeviceInfo();
    final m = (await ref.readManifest()).first;
    final good = (await ref.downloadDives([m]).toList())
        .whereType<DownloadedDive>()
        .single;

    final bad = DownloadedDive(
      manifest: _entry(1, 1700000000),
      data: Uint8List.fromList([1, 2, 3]),
    );
    final source =
        await ShearwaterDownloadSource.open(_FakeLink([bad, good]));
    final events = await source.download().toList();
    final outcomes = events
        .where((e) => e is DiveSourceDive || e is DiveSourceDiveFailed)
        .toList();
    expect(outcomes, hasLength(2));
    expect(outcomes[0], isA<DiveSourceDiveFailed>());
    expect((outcomes[0] as DiveSourceDiveFailed).listing!.diveNumber, 1);
    expect(outcomes[1], isA<DiveSourceDive>());
  });

  test('the mock transport works through the same source', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final source = await ShearwaterDownloadSource.open(
        MockBleTransport(perDiveDelay: Duration.zero));
    expect(source.identity.modelLabel, 'petrel3');
    final listings = await source.listDives();
    expect(listings.length, 8);
    final events =
        await source.download(selection: listings.take(2).toList()).toList();
    expect(events.whereType<DiveSourceDive>(), hasLength(2));
    await source.close();
  });
}
