import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/dev/fixture_seeder.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seedFixtures populates an empty DB by default', () async {
    SharedPreferences.setMockInitialValues(const {});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('uid-seed');

    await seedFixtures(db, psDb: ps, session: session);

    final dives = await DiveDao(db, ps, session).getAllDives();
    expect(dives, isNotEmpty,
        reason: 'expected fixture dives to land in an empty DB');
  });

  test('seedFixtures is a no-op once the user has reset', () async {
    SharedPreferences.setMockInitialValues(
        const {'fixtures_blocked_after_reset': true});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('uid-seed');

    await seedFixtures(db, psDb: ps, session: session);

    final dives = await DiveDao(db, ps, session).getAllDives();
    expect(dives, isEmpty,
        reason: 'reset flag must keep the DB empty across launches');
  });

  test('markFixturesBlocked sets the flag for subsequent seedFixtures calls',
      () async {
    SharedPreferences.setMockInitialValues(const {});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('uid-seed');

    await markFixturesBlocked();
    await seedFixtures(db, psDb: ps, session: session);

    final dives = await DiveDao(db, ps, session).getAllDives();
    expect(dives, isEmpty);
  });
}
