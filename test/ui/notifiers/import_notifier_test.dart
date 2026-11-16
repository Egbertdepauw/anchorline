import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/db/import_state_dao.dart';
import 'package:ccrlogger/devices/dive_download_source.dart';
import 'package:ccrlogger/shearwater/ble/mock_ble_transport.dart';
import 'package:ccrlogger/shearwater/ble/shearwater_ble_transport.dart';
import 'package:ccrlogger/shearwater/ble/shearwater_link.dart';
import 'package:ccrlogger/shearwater/parser/manifest_parser.dart';
import 'package:ccrlogger/ui/notifiers/import_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

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
}
