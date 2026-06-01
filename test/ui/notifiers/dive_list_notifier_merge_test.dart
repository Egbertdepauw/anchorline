import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/dive_merge_dao.dart';
import 'package:ccrlogger/ui/notifiers/dive_list_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  late AppDatabase db;
  late DiveListNotifier notifier;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('test-user');
    final diveDao = DiveDao(db, ps, session);
    final annDao = DiveAnnotationsDao(ps, session);
    final mergeDao = DiveMergeDao(db, ps, session);
    notifier = DiveListNotifier(diveDao, annDao, mergeDao);
  });

  tearDown(() async {
    notifier.dispose();
    await db.close();
  });

  test('selection mode toggles and tracks ids', () {
    notifier.enterSelectionMode('d1');
    expect(notifier.selectionMode, isTrue);
    expect(notifier.isSelected('d1'), isTrue);
    notifier.toggleSelected('d2');
    expect(notifier.selectedDiveIds, {'d1', 'd2'});
    notifier.exitSelectionMode();
    expect(notifier.selectionMode, isFalse);
    expect(notifier.selectedDiveIds, isEmpty);
  });
}
