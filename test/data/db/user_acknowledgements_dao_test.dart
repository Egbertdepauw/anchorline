import 'package:ccrlogger/data/db/user_acknowledgements_dao.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const subject = 'planner_warning';

  test('nothing is accepted until accept is called', () async {
    final ps = await openPowerSyncForTest();
    final dao = UserAcknowledgementsDao(ps, FakeSessionSource()..setUserId('u1'));

    expect(await dao.isAccepted(subject, 1), isFalse);
    await dao.accept(subject, 1);
    expect(await dao.isAccepted(subject, 1), isTrue);
    expect(await dao.isAccepted('other_subject', 1), isFalse);
  });

  test('accept stores the owner, version and sync metadata', () async {
    final ps = await openPowerSyncForTest();
    final dao = UserAcknowledgementsDao(ps, FakeSessionSource()..setUserId('u1'));

    await dao.accept(subject, 3);

    final row = (await ps.getAll('SELECT * FROM user_acknowledgements')).single;
    expect(row['owner_id'], 'u1');
    expect(row['subject'], subject);
    expect(row['text_version'], 3);
    expect(row['accepted_at'], isA<int>());
    expect(row['created_at'], row['accepted_at']);
    expect(row['updated_at'], row['accepted_at']);
    expect(row['deleted_at'], isNull);
    expect(row['version'], 1);
    expect(row['sync_status'], 0);
    expect((row['id'] as String).length, 36);
  });

  test('a later text version counts, an older one does not', () async {
    final ps = await openPowerSyncForTest();
    final dao = UserAcknowledgementsDao(ps, FakeSessionSource()..setUserId('u1'));

    await dao.accept(subject, 2);
    expect(await dao.isAccepted(subject, 1), isTrue);
    expect(await dao.isAccepted(subject, 2), isTrue);
    expect(await dao.isAccepted(subject, 3), isFalse);
  });

  test('signed out, the acceptance is stored with no owner', () async {
    final ps = await openPowerSyncForTest();
    final dao = UserAcknowledgementsDao(ps, FakeSessionSource());

    await dao.accept(subject, 1);

    expect(await dao.isAccepted(subject, 1), isTrue);
    final row = (await ps.getAll('SELECT owner_id FROM user_acknowledgements'))
        .single;
    expect(row['owner_id'], isNull);
  });

  test(
      'signed in, an acceptance made on this device while signed out still '
      'counts before the backfiller claims it', () async {
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource();
    final dao = UserAcknowledgementsDao(ps, session);
    await dao.accept(subject, 1);

    session.setUserId('u1');
    expect(await dao.isAccepted(subject, 1), isTrue);
  });

  test("another account's acceptance doesn't count", () async {
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('someone-else');
    final dao = UserAcknowledgementsDao(ps, session);
    await dao.accept(subject, 1);

    session.setUserId('u1');
    expect(await dao.isAccepted(subject, 1), isFalse);
  });

  test('a soft-deleted acceptance does not count', () async {
    final ps = await openPowerSyncForTest();
    final dao = UserAcknowledgementsDao(ps, FakeSessionSource()..setUserId('u1'));
    await dao.accept(subject, 1);
    await ps.execute('UPDATE user_acknowledgements SET deleted_at = 1');

    expect(await dao.isAccepted(subject, 1), isFalse);
  });

  test('watchChanges watches a valid query', () async {
    final ps = await openPowerSyncForTest();
    final dao = UserAcknowledgementsDao(ps, FakeSessionSource()..setUserId('u1'));

    await dao.watchChanges().first.timeout(const Duration(seconds: 5));
  });
}
