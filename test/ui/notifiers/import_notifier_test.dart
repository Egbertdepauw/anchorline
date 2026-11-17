import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/import/import_problem_reporter.dart' show UnusableParse;
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/db/import_state_dao.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:subsurface_core/data/models/dive.dart' as model;
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:subsurface_core/subsurface_core.dart'
    show kSubsurfaceImportedParserVersion;
import 'package:ccrlogger/devices/dive_download_source.dart';
import 'package:ccrlogger/devices/libdc/libdc_download_source.dart'
    show LibdcRun;
import 'package:ccrlogger/shearwater/ble/mock_ble_transport.dart';
import 'package:ccrlogger/shearwater/ble/shearwater_ble_transport.dart';
import 'package:ccrlogger/shearwater/ble/shearwater_link.dart';
import 'package:ccrlogger/shearwater/parser/manifest_parser.dart';
import 'package:ccrlogger/ui/notifiers/import_notifier.dart';
import 'package:ccrlogger/shearwater/ble/ble_io_impl.dart'
    show shearwaterServiceUuid;
import 'package:ccrlogger/ble/ble_central.dart' show BleScanResult;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../_helpers/fake_ble_central.dart';
import '../../_helpers/powersync_test_helper.dart';

/// The mock transport with scripted misbehaviour and call recording.
class _ScriptedLink implements ShearwaterLink {
  final MockBleTransport _inner =
      MockBleTransport(perDiveDelay: Duration.zero);

  /// Dive numbers whose downloaded blob is garbage.
  final Set<int> corrupt;

  /// Throw after this many dives have been emitted.
  final int? errorAfterDives;

  final List<Uint8List?> manifestFingerprints = [];
  int disconnects = 0;

  _ScriptedLink({this.corrupt = const {}, this.errorAfterDives});

  @override
  Future<DeviceInfo> readDeviceInfo() => _inner.readDeviceInfo();

  @override
  Future<List<ManifestEntry>> readManifest({Uint8List? lastFingerprint}) {
    manifestFingerprints.add(lastFingerprint);
    return _inner.readManifest(lastFingerprint: lastFingerprint);
  }

  /// Emits dives in exactly the order of [entries].
  @override
  Stream<DownloadEvent> downloadDives(List<ManifestEntry> entries) async* {
    var emitted = 0;
    await for (final e in _inner.downloadDives(entries)) {
      if (e is DownloadedDive) {
        if (errorAfterDives != null && emitted >= errorAfterDives!) {
          throw StateError('link dropped');
        }
        emitted++;
        yield corrupt.contains(e.manifest.diveNumber)
            ? DownloadedDive(
                manifest: e.manifest, data: Uint8List.fromList([1, 2, 3]))
            : e;
      } else {
        yield e;
      }
    }
  }

  @override
  Future<void> disconnect() async => disconnects++;
}

/// The mock transport, except that the second downloaded dive is garbage.
class _CorruptSecondDiveLink implements ShearwaterLink {
  final MockBleTransport _inner =
      MockBleTransport(perDiveDelay: Duration.zero);

  @override
  Future<DeviceInfo> readDeviceInfo() => _inner.readDeviceInfo();

  @override
  Future<List<ManifestEntry>> readManifest({Uint8List? lastFingerprint}) =>
      _inner.readManifest(lastFingerprint: lastFingerprint);

  @override
  Stream<DownloadEvent> downloadDives(List<ManifestEntry> entries) async* {
    var seen = 0;
    await for (final e in _inner.downloadDives(entries)) {
      if (e is DownloadedDive && ++seen == 2) {
        yield DownloadedDive(
            manifest: e.manifest, data: Uint8List.fromList([1, 2, 3]));
      } else {
        yield e;
      }
    }
  }

  @override
  Future<void> disconnect() => _inner.disconnect();
}

/// A [DiveDao] whose every import is rejected.
class _RejectingDao extends DiveDao {
  _RejectingDao(super.db, super.ps, super.session);

  @override
  Future<ImportOutcome> importDive({
    required ConvertedDive converted,
    required Uint8List rawBlob,
    required int parserVersion,
    bool matchSubsurfaceCopies = true,
  }) async =>
      ImportOutcome.rejected;
}

/// The mock dive [n] as a Subsurface copy: Subsurface's own id and logbook
/// number, a start time [shiftSeconds] away, legacy-free Shearwater vendor.
ConvertedDive _copyOfMockDive(int n,
    {int shiftSeconds = 3, int logbookNumber = 5}) {
  final parsed = ShearwaterDiveParser(model: ShearwaterModel.petrel3)
      .parse(File('test/fixtures/dives/dive_$n.bin').readAsBytesSync());
  final c = DiveConverter.convert(
    parsed: parsed,
    dcSerial: 0xB89641E4,
    dcDiveNumber: n,
    dcModel: ShearwaterModel.petrel3,
  );
  final d = c.dive;
  final shift = Duration(seconds: shiftSeconds);
  return ConvertedDive(
    dive: model.Dive(
      id: model.generateDiveId(0xB89641E4, logbookNumber,
          d.startTime.add(shift).millisecondsSinceEpoch ~/ 1000),
      dcSerial: d.dcSerial,
      dcDiveNumber: logbookNumber,
      startTime: d.startTime.add(shift),
      endTime: d.endTime.add(shift),
      utcOffsetMinutes: d.utcOffsetMinutes,
      duration: d.duration,
      maxDepthMeters: d.maxDepthMeters,
      diveMode: d.diveMode,
      decoModel: d.decoModel,
      gfLow: d.gfLow,
      gfHigh: d.gfHigh,
      atmosphericPressureMbar: d.atmosphericPressureMbar,
      waterDensityKgM3: d.waterDensityKgM3,
      logVersion: d.logVersion,
      dcModel: d.dcModel,
      gasMixes: d.gasMixes,
      tanks: d.tanks,
      sampleIntervalMs: d.sampleIntervalMs,
      sensorCalibration: d.sensorCalibration,
      configuredStackSeconds: d.configuredStackSeconds,
      stackRemainingAtStartSeconds: d.stackRemainingAtStartSeconds,
      stackRemainingAtEndSeconds: d.stackRemainingAtEndSeconds,
      dcVendor: d.dcVendor,
      dcProduct: d.dcProduct,
      dcFamily: d.dcFamily,
      dcModelCode: d.dcModelCode,
    ),
    samples: c.samples,
    events: c.events,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DiveDao dao;
  late ImportStateDao importStateDao;
  late ImportNotifier notifier;
  late EquipmentDao equipmentDao;
  late PowerSyncDatabase ps;
  final extra = <ImportNotifier>[];

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final equipmentRig = await openEquipmentDaoForTest(db);
    // Reuse the equipment rig's psDb so importDive's dive write + the
    // equipment-side reads share one PowerSync handle (matches how the
    // app wires them).
    dao = DiveDao(db, equipmentRig.ps, equipmentRig.session);
    importStateDao = ImportStateDao(db);
    equipmentDao = equipmentRig.dao;
    ps = equipmentRig.ps;
    notifier = ImportNotifier(
      dao: dao,
      importStateDao: importStateDao,
      equipmentDao: equipmentRig.dao,
      useMock: true,
      reporter: (e, st, where) {},
    );
  });

  tearDown(() async {
    for (final n in extra) {
      n.dispose();
    }
    extra.clear();
    notifier.dispose();
    await db.close();
  });

  test('starts in idle state', () {
    expect(notifier.state, equals(ImportFlowState.idle));
  });

  test('startScan transitions to scanning', () {
    notifier.startScan();
    expect(notifier.state, equals(ImportFlowState.scanning));
  });

  test('full mock flow reaches done state', () async {
    notifier.startScan();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(notifier.mockDeviceAvailable, isTrue);

    await notifier.selectMockDevice();
    expect(notifier.state, equals(ImportFlowState.readingManifest));
    expect(notifier.identity, isNotNull);

    await notifier.readManifestAndFilterNew();
    expect(notifier.newDives.length, equals(8));

    await notifier.downloadAll();
    expect(notifier.state, equals(ImportFlowState.done));
    expect(notifier.downloadedCount, equals(8));
  });

  test('retry resets to scanning', () {
    notifier.setError('test error');
    expect(notifier.state, equals(ImportFlowState.error));
    notifier.retry();
    expect(notifier.state, equals(ImportFlowState.scanning));
  });

  test('a failed dive counts as failed and the rest still import', () async {
    await notifier.connectLinkForTest(_CorruptSecondDiveLink());
    expect(notifier.state, equals(ImportFlowState.readingManifest));
    await notifier.readManifestAndFilterNew();
    expect(notifier.newDives.length, equals(8));

    await notifier.downloadAll();
    expect(notifier.state, equals(ImportFlowState.done));
    expect(notifier.failedCount, equals(1));
    expect(notifier.downloadedCount, equals(7));
  });

  test('the fingerprint is saved under identity.importStateKey', () async {
    await notifier.selectMockDevice();
    final key = notifier.identity!.importStateKey;
    await notifier.readManifestAndFilterNew();
    expect(await importStateDao.getLastFingerprint(key), isNull);

    await notifier.downloadAll();
    expect(notifier.downloadedCount, equals(8));
    expect(await importStateDao.getLastFingerprint(key), isNotNull);
  });

  ImportNotifier newNotifier() {
    final n = ImportNotifier(
      dao: dao,
      importStateDao: importStateDao,
      equipmentDao: equipmentDao,
      useMock: true,
      reporter: (e, st, where) {},
    );
    extra.add(n);
    return n;
  }

  /// Connects [n] through [link] and lists every dive on it.
  Future<List<DiveListing>> listAll(ImportNotifier n, ShearwaterLink link) async {
    await n.connectLinkForTest(link);
    n.forceFullReimport = true;
    await n.readManifestAndFilterNew();
    return n.newDives;
  }

  List<DiveListing> pick(List<DiveListing> all, List<int> numbers) => [
        for (final num in numbers) all.firstWhere((l) => l.diveNumber == num),
      ];

  Uint8List fpOf(int diveNumber) =>
      Uint8List.fromList([0, 0, 0, diveNumber & 0xFF]);

  test('the saved fingerprint is the last imported dive\'s, byte for byte',
      () async {
    final all = await listAll(notifier, _ScriptedLink());
    await notifier.downloadAll(pick(all, [713, 711, 712]));
    expect(notifier.downloadedCount, 3);
    expect(await importStateDao.getLastFingerprint('B89641E4'), fpOf(712));
  });

  test('a last dive that fails to parse leaves the fingerprint at the previous success',
      () async {
    final all = await listAll(notifier, _ScriptedLink(corrupt: {713}));
    await notifier.downloadAll(pick(all, [711, 712, 713]));
    expect(notifier.failedCount, 1);
    expect(await importStateDao.getLastFingerprint('B89641E4'), fpOf(712));
  });

  test('a last dive that is already stored leaves the fingerprint at the previous success',
      () async {
    final all = await listAll(notifier, _ScriptedLink());
    await notifier.downloadAll(pick(all, [711]));
    expect(await importStateDao.getLastFingerprint('B89641E4'), fpOf(711));

    final n2 = newNotifier();
    final all2 = await listAll(n2, _ScriptedLink());
    await n2.downloadAll(pick(all2, [712, 711]));
    expect(n2.downloadedCount, 1);
    expect(await importStateDao.getLastFingerprint('B89641E4'), fpOf(712));
  });

  test('a stream error after dive 1 ends in error, keeps dive 1\'s fingerprint and disconnects',
      () async {
    final link = _ScriptedLink(errorAfterDives: 1);
    final all = await listAll(notifier, link);
    await notifier.downloadAll(pick(all, [711, 712, 713]));
    expect(notifier.state, ImportFlowState.error);
    expect(notifier.errorMessage,
        'Connection lost. 1 of 3 dives downloaded.');
    expect(notifier.downloadedCount, 1);
    expect(await importStateDao.getLastFingerprint('B89641E4'), fpOf(711));
    expect(link.disconnects, 1);
  });

  test('readManifest receives the saved fingerprint, and null under forceFullReimport',
      () async {
    final all = await listAll(notifier, _ScriptedLink());
    await notifier.downloadAll(pick(all, [711]));

    final link = _ScriptedLink();
    final n2 = newNotifier();
    await n2.connectLinkForTest(link);
    await n2.readManifestAndFilterNew();
    expect(link.manifestFingerprints.single, fpOf(711));

    final link3 = _ScriptedLink();
    final n3 = newNotifier();
    await n3.connectLinkForTest(link3);
    n3.forceFullReimport = true;
    await n3.readManifestAndFilterNew();
    expect(link3.manifestFingerprints.single, isNull);
  });

  test('connecting registers the computer without a libdivecomputer model code',
      () async {
    await notifier.connectLinkForTest(_ScriptedLink());
    final row = await ps.get(
        'SELECT dc_vendor, dc_product, model, dc_model_code, dc_family '
        'FROM dive_computers');
    expect(row['dc_vendor'], 'Shearwater');
    expect(row['dc_product'], 'Petrel 3');
    expect(row['model'], 0xB407);
    expect(row['dc_model_code'], isNull);
    expect(row['dc_family'], isNull);
  });

  group('import outcomes', () {
    final reports = <(Object, String)>[];
    late ImportNotifier reporting;

    ImportNotifier withReporter({DiveDao? useDao}) {
      final n = ImportNotifier(
        dao: useDao ?? dao,
        importStateDao: importStateDao,
        equipmentDao: equipmentDao,
        useMock: true,
        reporter: (e, st, where) => reports.add((e, where)),
      );
      extra.add(n);
      return n;
    }

    setUp(() {
      reports.clear();
      reporting = withReporter();
    });

    Future<void> storeCopy(ConvertedDive c) async {
      final out = await dao.importDive(
        converted: c,
        rawBlob: Uint8List(0),
        parserVersion: kSubsurfaceImportedParserVersion,
        matchSubsurfaceCopies: false,
      );
      expect(out, ImportOutcome.inserted);
    }

    test('a refreshed dive counts as downloaded and moves the fingerprint',
        () async {
      await storeCopy(_copyOfMockDive(711));
      final all = await listAll(reporting, _ScriptedLink());
      await reporting.downloadAll(pick(all, [711]));
      expect(reporting.downloadedCount, 1);
      expect(reporting.refreshedCount, 1);
      expect(reporting.failedCount, 0);
      expect(await importStateDao.getLastFingerprint('B89641E4'), fpOf(711));
      expect(reports, isEmpty);
    });

    test('an unchanged dive is not counted', () async {
      final all = await listAll(notifier, _ScriptedLink());
      await notifier.downloadAll(pick(all, [711, 712]));
      expect(await importStateDao.getLastFingerprint('B89641E4'), fpOf(712));

      final all2 = await listAll(reporting, _ScriptedLink());
      await reporting.downloadAll(pick(all2, [711]));
      expect(reporting.downloadedCount, 0);
      expect(reporting.refreshedCount, 0);
      expect(reporting.failedCount, 0);
      expect(await importStateDao.getLastFingerprint('B89641E4'), fpOf(712));
      expect(reports, isEmpty);
    });

    test('a rejected dive counts as failed and is reported once', () async {
      final rig = await openEquipmentDaoForTest(db);
      final rejecting = withReporter(
          useDao: _RejectingDao(db, rig.ps, rig.session));
      final all = await listAll(rejecting, _ScriptedLink());
      await rejecting.downloadAll(pick(all, [711]));
      expect(rejecting.failedCount, 1);
      expect(rejecting.downloadedCount, 0);
      expect(reports, hasLength(1));
      expect(reports.single.$2, 'download');
      expect(reports.single.$1, isA<UnusableParse>());
      expect(await importStateDao.getLastFingerprint('B89641E4'), isNull);
    });

    test('a dive that fails to parse is reported once', () async {
      final all = await listAll(reporting, _ScriptedLink(corrupt: {712}));
      await reporting.downloadAll(pick(all, [711, 712]));
      expect(reporting.failedCount, 1);
      expect(reports, hasLength(1));
      expect(reports.single.$2, 'download');
    });

    test('the manifest hides a copy refreshed by an earlier download',
        () async {
      // A refresh keeps the copy's id and takes the download's dive number
      // and version. The mock's manifest times are not those of its dive
      // files, so the stored row is placed at the manifest's start time.
      final probe = await listAll(reporting, _ScriptedLink());
      final listing = probe.firstWhere((l) => l.diveNumber == 711);
      final base = _copyOfMockDive(711, shiftSeconds: 0);
      final shift = listing.startTimestamp -
              base.dive.startTime.millisecondsSinceEpoch ~/ 1000 +
          3;
      final refreshed = _copyOfMockDive(711,
          shiftSeconds: shift, logbookNumber: 711);
      final out = await dao.importDive(
        converted: refreshed,
        rawBlob: Uint8List.fromList([1]),
        parserVersion: 1,
        matchSubsurfaceCopies: false,
      );
      expect(out, ImportOutcome.inserted);
      expect(refreshed.dive.id, isNot(listing.diveId));

      final n2 = withReporter();
      await n2.connectLinkForTest(_ScriptedLink());
      await n2.readManifestAndFilterNew();
      final numbers = n2.newDives.map((l) => l.diveNumber);
      expect(numbers, isNot(contains(711)));
      expect(numbers, contains(712));
    });
  });

  group('scan', () {
    late FakeBleCentral central;
    late ImportNotifier scanner;

    setUp(() async {
      central = FakeBleCentral();
      scanner = ImportNotifier(
        dao: dao,
        importStateDao: importStateDao,
        equipmentDao: equipmentDao,
        reporter: (e, st, where) {},
        central: central,
      );
      extra.add(scanner);
      scanner.startScan();
      // The scan starts after the adapter check.
      await Future<void>.delayed(Duration.zero);
    });

    BleScanResult petrel() => const BleScanResult(
        id: 'AA:01',
        name: 'Petrel 3',
        serviceUuids: [shearwaterServiceUuid]);

    test('a Petrel and an OSTC in one scan: one shearwater, one libdc result',
        () async {
      central.advertise(petrel());
      central.advertise(const BleScanResult(id: 'BB:02', name: 'OSTC 4-1234'));
      await Future<void>.delayed(Duration.zero);

      expect(central.scans, [<String>[]], reason: 'one scan, no filter');
      final found = scanner.discoveredDevices;
      expect(found.map((d) => d.kind),
          [ImportDeviceKind.shearwater, ImportDeviceKind.libdc]);
      expect(found[0].id, 'AA:01');
      expect(found[0].candidates, isEmpty);
      expect(found[1].id, 'BB:02');
      expect(found[1].name, 'OSTC 4-1234');
      expect(found[1].candidates, isNotEmpty);
      expect(found[1].candidates.every((c) => !c.isShearwater), isTrue);

      // The same device again is not listed twice.
      central.advertise(petrel());
      await Future<void>.delayed(Duration.zero);
      expect(scanner.discoveredDevices, hasLength(2));
    });

    test('a Shearwater name never becomes a libdc candidate', () async {
      // No service UUID in the advertisement, so it is not "shearwater" by
      // kind either; the name must still not match a libdivecomputer model.
      central.advertise(const BleScanResult(id: 'CC:03', name: 'Petrel 3'));
      central.advertise(const BleScanResult(id: 'DD:04', name: 'Perdix 2'));
      await Future<void>.delayed(Duration.zero);

      for (final d in scanner.discoveredDevices) {
        expect(d.kind, ImportDeviceKind.unmatched, reason: d.name);
        expect(d.candidates, isEmpty);
      }
      expect(Libdc.matchBle('Petrel 3').any((c) => c.isShearwater), isFalse);
    });

    test(
        'an unnamed device is not listed; a named unmatched one is offered '
        'to the picker', () async {
      central.advertise(const BleScanResult(id: 'EE:05', name: ''));
      central.advertise(
          const BleScanResult(id: 'FF:06', name: 'Some Headphones'));
      await Future<void>.delayed(Duration.zero);

      expect(scanner.discoveredDevices.map((d) => d.id), ['FF:06']);
      expect(scanner.discoveredDevices.single.kind,
          ImportDeviceKind.unmatched);
    });

    test('recordNextDownload defaults to false and can be set', () {
      expect(scanner.recordNextDownload, isFalse);
      scanner.recordNextDownload = true;
      expect(scanner.recordNextDownload, isTrue);
    });
  });

  group('libdc download', () {
    const descriptor = LibdcDescriptor(
        vendor: 'Divesoft',
        product: 'Liberty',
        family: 0x130000,
        model: 10,
        transports: 32);
    const scan = ImportScanResult(
        id: 'AA:11',
        name: 'Liberty 1234',
        kind: ImportDeviceKind.libdc,
        candidates: [descriptor]);
    const key = 'libdc:${0x130000}:1234';

    LibdcEnvelope envelope(int n) => LibdcEnvelope(
          pinnedCommit: '0194f09',
          vendor: 'Divesoft',
          product: 'Liberty',
          family: 0x130000,
          descriptorModel: 10,
          devinfoModel: 10,
          devinfoFirmware: 7,
          devinfoSerial: 1234,
          fingerprint: Uint8List.fromList([n & 0xFF, n >> 8, 1, 2]),
          data: Uint8List.fromList([1, 2, 3]),
        );

    LibdcDiveDownloaded good(int n) => LibdcDiveDownloaded(
          envelope: envelope(n),
          diveId: 'x$n',
          converted: _copyOfMockDive(n, shiftSeconds: 0, logbookNumber: n),
        );

    LibdcDiveDownloaded bad(int n) => LibdcDiveDownloaded(
          envelope: envelope(n),
          diveId: 'bad$n',
          parseError: LibdcStatus.dataFormat,
        );

    LibdcFinished finished(LibdcStatus s) => LibdcFinished(
        status: s, recording: LibdcRecording(log: ['the log line']));

    const info = LibdcDeviceInfo(model: 10, firmware: 7, serial: 1234);

    var closes = 0;
    var cancels = 0;
    Map<int, Uint8List>? passedKnown;
    bool? passedRecord;

    ImportNotifier libdcNotifier(List<LibdcDownloadEvent> script,
        {bool failConnect = false}) {
      closes = 0;
      cancels = 0;
      passedKnown = null;
      passedRecord = null;
      final n = ImportNotifier(
        dao: dao,
        importStateDao: importStateDao,
        equipmentDao: equipmentDao,
        reporter: (e, st, where) {},
        central: FakeBleCentral(),
        libdcOpener: (central, r, d) async {
          if (failConnect) throw StateError('no gatt');
          return LibdcOpened(
            connection: LibdcBleConnection(_NoLink()),
            close: () async => closes++,
            gattSummary: const ['service 1', 'char 2'],
          );
        },
        libdcStarter: ({
          required descriptor,
          required connection,
          required knownFingerprints,
          required record,
        }) {
          passedKnown = knownFingerprints;
          passedRecord = record;
          return LibdcRun(
              events: Stream.fromIterable(script), cancel: () => cancels++);
        },
      );
      extra.add(n);
      return n;
    }

    test('a libdc download skips the manifest and imports each dive',
        () async {
      final n = libdcNotifier(
          [info, good(711), good(712), finished(LibdcStatus.done)]);
      final states = <ImportFlowState>[];
      n.addListener(() => states.add(n.state));

      await n.selectLibdcDevice(scan, descriptor);

      expect(states, isNot(contains(ImportFlowState.readingManifest)));
      expect(states, contains(ImportFlowState.connecting));
      expect(states, contains(ImportFlowState.downloading));
      expect(n.state, ImportFlowState.done);
      expect(n.downloadedCount, 2);
      expect(n.failedCount, 0);
      expect(n.identity!.vendor, 'Divesoft');
      expect(closes, greaterThan(0));
      expect(n.lastRecordingText, contains('the log line'));
      expect(n.lastGattSummary, ['service 1', 'char 2']);
      expect(n.isLibdcDownload, isTrue);
    });

    test('the fingerprint is saved after a clean finish with no failures only',
        () async {
      final n = libdcNotifier(
          [info, good(711), good(712), finished(LibdcStatus.done)]);
      await n.selectLibdcDevice(scan, descriptor);
      // The computer sends the newest dive first: 711's fingerprint.
      expect(await importStateDao.getLastFingerprint(key),
          envelope(711).fingerprint);
    });

    test('a failed dive keeps the old fingerprint', () async {
      final old = Uint8List.fromList([9, 9, 9, 9]);
      await importStateDao.saveLastFingerprint(key, old);
      final n = libdcNotifier(
          [info, good(711), bad(712), finished(LibdcStatus.done)]);
      await n.selectLibdcDevice(scan, descriptor);
      expect(n.failedCount, 1);
      expect(n.downloadedCount, 1);
      expect(await importStateDao.getLastFingerprint(key), old);
    });

    test('download everything again passes no fingerprints', () async {
      await importStateDao.saveLastFingerprint(
          key, Uint8List.fromList([9, 9, 9, 9]));

      final normal = libdcNotifier([info, finished(LibdcStatus.done)]);
      await normal.selectLibdcDevice(scan, descriptor);
      expect(passedKnown, {1234: Uint8List.fromList([9, 9, 9, 9])});
      expect(passedRecord, isFalse);

      final again = libdcNotifier([info, finished(LibdcStatus.done)]);
      again.forceFullReimport = true;
      again.recordNextDownload = true;
      await again.selectLibdcDevice(scan, descriptor);
      expect(passedKnown, isEmpty);
      expect(passedRecord, isTrue);
    });

    test('a failed libdc download says how many dives were saved', () async {
      final n =
          libdcNotifier([info, good(711), finished(LibdcStatus.timeout)]);
      await n.selectLibdcDevice(scan, descriptor);
      expect(n.state, ImportFlowState.error);
      expect(n.errorMessage,
          'Download stopped (the computer stopped answering). 1 dives saved.');
      expect(n.lastRecordingText, contains('the log line'));
      expect(await importStateDao.getLastFingerprint(key), isNull);
    });

    test('the stop reason per status', () {
      expect(libdcStopReason(LibdcStatus.timeout),
          'the computer stopped answering');
      expect(libdcStopReason(LibdcStatus.io), 'the connection dropped');
      expect(libdcStopReason(LibdcStatus.protocol),
          'unexpected data from the computer');
      expect(libdcStopReason(LibdcStatus.cancelled), 'cancelled');
      expect(libdcStopReason(LibdcStatus.noAccess), 'error noAccess');
    });

    test('a connect failure ends in the error state, not an exception',
        () async {
      final n = libdcNotifier(const [], failConnect: true);
      await n.selectLibdcDevice(scan, descriptor);
      expect(n.state, ImportFlowState.error);
      expect(n.errorMessage, startsWith('Connection failed'));
      expect(n.lastRecordingText, isNull);
    });

    test('cancelling stops the running download', () async {
      final n = libdcNotifier([info, finished(LibdcStatus.cancelled)]);
      await n.selectLibdcDevice(scan, descriptor);
      n.cancelDownload();
      expect(cancels, greaterThan(0));
    });
  });
}

class _NoLink implements LibdcBleLink {
  @override
  String get advertisedName => 'fake';
  @override
  Stream<Uint8List> get notifications => const Stream.empty();
  @override
  Future<void> write(Uint8List bytes) async {}
  @override
  Future<Uint8List> readCharacteristic(String uuid) async => Uint8List(0);
  @override
  Future<void> writeCharacteristic(String uuid, Uint8List bytes) async {}
  @override
  Future<void> get disconnected => Completer<void>().future;
}
