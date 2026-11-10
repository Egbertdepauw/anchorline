import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('divemaster round-trips through upsert + get', () async {
    final psDb = await openPowerSyncForTest();
    final dao = DiveAnnotationsDao(psDb, FakeSessionSource());
    final now = DateTime.utc(2026, 5, 12);
    final ann = DiveAnnotation(
      diveId: 'dive_dm_1',
      divemaster: 'Alex Marlin',
      createdAt: now,
      updatedAt: now,
    );

    await dao.upsert(ann);
    final back = await dao.get('dive_dm_1');

    expect(back, isNotNull);
    expect(back!.divemaster, 'Alex Marlin');
  });

  test('divemaster null round-trips as null', () async {
    final psDb = await openPowerSyncForTest();
    final dao = DiveAnnotationsDao(psDb, FakeSessionSource());
    final now = DateTime.utc(2026, 5, 12);
    final ann = DiveAnnotation(
      diveId: 'dive_dm_2',
      createdAt: now,
      updatedAt: now,
    );

    await dao.upsert(ann);
    final back = await dao.get('dive_dm_2');

    expect(back, isNotNull);
    expect(back!.divemaster, isNull);
  });
}
