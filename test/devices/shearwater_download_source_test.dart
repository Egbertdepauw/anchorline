import 'dart:io';
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
      [
        for (final e in events)
          if (e is DownloadedDive)
            e.manifest
          else if (e is DownloadRefusedDive)
            e.manifest,
      ];

  @override
  Stream<DownloadEvent> downloadDives(List<ManifestEntry> entries) =>
      Stream.fromIterable(events);

  @override
  Future<void> disconnect() async {}
}

/// The device's own manifest entries for the eight fixture dives (711-718).
List<ManifestEntry> _fixtureEntries() => ManifestParser.parse(
        File('test/fixtures/manifest.bin').readAsBytesSync())
    .where((e) => e.diveNumber >= 711 && e.diveNumber <= 718)
    .toList();

Uint8List _fixtureBlob(int diveNumber) =>
    File('test/fixtures/dives/dive_$diveNumber.bin').readAsBytesSync();

/// A copy of [e] with another dive number or start time, as a stale
/// manifest could list it.
ManifestEntry _restamped(ManifestEntry e, {int? diveNumber, int? start}) =>
    ManifestEntry(
      header: e.header,
      diveNumber: diveNumber ?? e.diveNumber,
      fingerprint: e.fingerprint,
      startTimestamp: start ?? e.startTimestamp,
      endTimestamp: e.endTimestamp,
      address: e.address,
      endAddress: e.endAddress,
    );

/// A link that lists [manifest] and answers each entry with the fixture
/// blob of the dive [blobFor] names (its own dive by default), so a test
/// can hand an entry another dive's bytes.
class _FixtureLink implements ShearwaterLink {
  final List<ManifestEntry> manifest;
  final Map<int, int> blobFor;
  _FixtureLink(this.manifest, {this.blobFor = const {}});

  @override
  Future<DeviceInfo> readDeviceInfo() => _FakeLink(const []).readDeviceInfo();

  @override
  Future<List<ManifestEntry>> readManifest({Uint8List? lastFingerprint}) async =>
      manifest;

  @override
  Stream<DownloadEvent> downloadDives(List<ManifestEntry> entries) async* {
    for (final e in entries) {
      yield DownloadedDive(
        manifest: e,
        data: _fixtureBlob(blobFor[e.diveNumber] ?? e.diveNumber),
      );
    }
  }

  @override
  Future<void> disconnect() async {}
}

/// The dive or failure for each downloaded entry, keyed by dive number.
Future<Map<int, DiveSourceEvent>> _outcomes(ShearwaterLink link) async {
  final source = await ShearwaterDownloadSource.open(link);
  final events = await source.download().toList();
  return {
    for (final e in events)
      if (e is DiveSourceDive)
        e.listing!.diveNumber: e
      else if (e is DiveSourceDiveFailed)
        e.listing!.diveNumber: e,
  };
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
    expect(id.modelCode, isNull);
    expect(id.family, isNull);
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
      expect(got.converted.dive.id, got.listing!.diveId);
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
      expect(a.dcModel, b.dcModel);
      expect(a.sampleIntervalMs, b.sampleIntervalMs);
      expect([for (final g in a.gasMixes) g.toJson()],
          [for (final g in b.gasMixes) g.toJson()]);
      expect([for (final t in a.tanks) t.toJson()],
          [for (final t in b.tanks) t.toJson()]);
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

  test('a dive the computer refuses yields DiveSourceDiveRefused and the next dive still arrives',
      () async {
    final ref = _traceTransport();
    await ref.readDeviceInfo();
    final m = (await ref.readManifest()).first;
    final good = (await ref.downloadDives([m]).toList())
        .whereType<DownloadedDive>()
        .single;

    final refused =
        DownloadRefusedDive(manifest: _entry(1, 1700000000), errorCode: 0x31);
    final source =
        await ShearwaterDownloadSource.open(_FakeLink([refused, good]));
    final events = await source.download().toList();
    final outcomes = events
        .where((e) =>
            e is DiveSourceDive ||
            e is DiveSourceDiveFailed ||
            e is DiveSourceDiveRefused)
        .toList();
    expect(outcomes, hasLength(2));
    final r = outcomes[0] as DiveSourceDiveRefused;
    expect(r.listing.diveNumber, 1);
    expect(r.listing.diveId, generateDiveId(0xB89641E4, 1, 1700000000));
    expect(r.errorCode, 0x31);
    expect(outcomes[1], isA<DiveSourceDive>());
  });

  test('correctly paired dives keep the dive id their manifest entry gives',
      () async {
    final out = await _outcomes(_FixtureLink(_fixtureEntries()));
    expect(out.keys, unorderedEquals([711, 712, 713, 714, 715, 716, 717, 718]));
    for (final e in _fixtureEntries()) {
      final dive = out[e.diveNumber]! as DiveSourceDive;
      final id = generateDiveId(0xB89641E4, e.diveNumber, e.startTimestamp);
      expect(dive.listing!.diveId, id);
      expect(dive.converted.dive.id, id);
      expect(dive.converted.dive.dcDiveNumber, e.diveNumber);
    }
  });

  test('a blob that belongs to another entry fails that entry only', () async {
    // A stale manifest: the entry for 717 comes back with 718's bytes.
    final out = await _outcomes(
        _FixtureLink(_fixtureEntries(), blobFor: {717: 718}));
    expect(out.keys, unorderedEquals([711, 712, 713, 714, 715, 716, 717, 718]));

    final failed = out[717];
    expect(failed, isA<DiveSourceDiveFailed>());
    final error = (failed! as DiveSourceDiveFailed).error;
    expect(error, isA<ManifestMismatchException>());
    final mismatch = error as ManifestMismatchException;
    expect(mismatch.entry.diveNumber, 717);
    expect(mismatch.blobDiveNumber, 718);
    expect(mismatch.blobStartTimestamp, 0x69E4A356);

    for (final n in [711, 712, 713, 714, 715, 716, 718]) {
      expect(out[n], isA<DiveSourceDive>(), reason: 'dive $n');
    }
    // 718 itself still arrives under its own id, once.
    final e718 = _fixtureEntries().firstWhere((e) => e.diveNumber == 718);
    expect((out[718]! as DiveSourceDive).converted.dive.id,
        generateDiveId(0xB89641E4, 718, e718.startTimestamp));
  });

  test('a blob with the entry\'s start time but another dive number fails',
      () async {
    final e718 = _fixtureEntries().firstWhere((e) => e.diveNumber == 718);
    // The entry says 4242; the blob (718's) says 718.
    final out = await _outcomes(_FixtureLink(
        [_restamped(e718, diveNumber: 4242)],
        blobFor: {4242: 718}));
    final failed = out[4242];
    expect(failed, isA<DiveSourceDiveFailed>());
    expect((failed! as DiveSourceDiveFailed).error,
        isA<ManifestMismatchException>());
  });

  test('a blob with the entry\'s dive number but another start time fails',
      () async {
    final e718 = _fixtureEntries().firstWhere((e) => e.diveNumber == 718);
    final out = await _outcomes(_FixtureLink(
        [_restamped(e718, start: e718.startTimestamp + 60)]));
    final failed = out[718];
    expect(failed, isA<DiveSourceDiveFailed>());
    expect((failed! as DiveSourceDiveFailed).error,
        isA<ManifestMismatchException>());
  });

  test('the trace transport pairs every dive with its own entry', () async {
    // Ascending-address requests against a trace recorded newest first:
    // every dive must still land under its own manifest entry.
    final source = await ShearwaterDownloadSource.open(_traceTransport());
    final listings = await source.listDives();
    final events =
        await source.download(selection: listings.take(3).toList()).toList();
    expect(events.whereType<DiveSourceDiveFailed>(), isEmpty);
    final dives = events.whereType<DiveSourceDive>().toList();
    expect(dives, hasLength(3));
    for (final d in dives) {
      expect(d.converted.dive.id, d.listing!.diveId);
      expect(d.rawBlob, _fixtureBlob(d.listing!.diveNumber));
    }
  });

  test('a selection entry the source never listed throws StateError', () async {
    final source = await ShearwaterDownloadSource.open(_traceTransport());
    final listings = await source.listDives();
    final stranger = DiveListing(
      diveNumber: 99999,
      startTimestamp: 1,
      endTimestamp: 2,
      fingerprint: Uint8List.fromList([9, 9, 9, 9]),
      diveId: 'not-in-the-manifest',
    );
    await expectLater(
      source.download(selection: [listings.first, stranger]).toList(),
      throwsStateError,
    );
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
