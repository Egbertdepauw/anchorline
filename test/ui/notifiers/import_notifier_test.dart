import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/db/import_state_dao.dart';
import 'package:ccrlogger/ui/notifiers/import_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DiveDao dao;
  late ImportStateDao importStateDao;
  late ImportNotifier notifier;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = DiveDao(db);
    importStateDao = ImportStateDao(db);
    notifier = ImportNotifier(
      dao: dao,
      importStateDao: importStateDao,
      equipmentDao: EquipmentDao(db),
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
    expect(notifier.deviceInfo, isNotNull);

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
}
