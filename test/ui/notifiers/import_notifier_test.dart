import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/import_state_dao.dart';
import 'package:ccrlogger/shearwater/ble/mock_ble_transport.dart';
import 'package:ccrlogger/shearwater/ble/shearwater_ble_transport.dart';
import 'package:ccrlogger/shearwater/ble/shearwater_link.dart';
import 'package:ccrlogger/shearwater/parser/manifest_parser.dart';
import 'package:ccrlogger/ui/notifiers/import_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

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

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final equipmentRig = await openEquipmentDaoForTest(db);
    // Reuse the equipment rig's psDb so importDive's dive write + the
    // equipment-side reads share one PowerSync handle (matches how the
    // app wires them).
    dao = DiveDao(db, equipmentRig.ps, equipmentRig.session);
    importStateDao = ImportStateDao(db);
    notifier = ImportNotifier(
      dao: dao,
      importStateDao: importStateDao,
      equipmentDao: equipmentRig.dao,
      useMock: true,
    );
  });

  tearDown(() async {
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
}
