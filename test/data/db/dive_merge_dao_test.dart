import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_merge_dao.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  late AppDatabase db;
  late DiveMergeDao dao;
  late DiveMergeDaoTestRig rig;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    rig = await openDiveMergeDaoForTest(db);
    dao = rig.dao;
  });

  tearDown(() async => db.close());

  test('generateMergeGroupId is order-independent and stable', () {
    expect(generateMergeGroupId(['a', 'b']), generateMergeGroupId(['b', 'a']));
    expect(generateMergeGroupId(['a', 'b']), hasLength(32));
    expect(generateMergeGroupId(['a', 'b']) != generateMergeGroupId(['a', 'c']),
        isTrue);
  });

  test('mergeDives links dives under one group; getActiveLinks returns them',
      () async {
    final groupId = await dao.mergeDives(['d1', 'd2', 'd3']);
    final links = await dao.getActiveLinks();
    expect(links, hasLength(3));
    expect(links.every((l) => l.groupId == groupId), isTrue);
    expect(links.map((l) => l.diveId).toSet(), {'d1', 'd2', 'd3'});
  });

  test('unmerge soft-deletes all links in the group', () async {
    final groupId = await dao.mergeDives(['d1', 'd2']);
    await dao.unmerge(groupId);
    expect(await dao.getActiveLinks(), isEmpty);
  });

  test('re-merging a previously-unmerged dive reactivates its link', () async {
    final g1 = await dao.mergeDives(['d1', 'd2']);
    await dao.unmerge(g1);
    final g2 = await dao.mergeDives(['d1', 'd2']);
    final links = await dao.getActiveLinks();
    expect(links, hasLength(2));
    expect(links.every((l) => l.groupId == g2), isTrue);
  });

  Future<int?> ownerCount(String diveId) async {
    final row = await rig.ps.getOptional(
      'SELECT owner_id FROM dive_merge_links WHERE id = ?',
      [diveId],
    );
    return row?['owner_id'] == 'test-user' ? 1 : 0;
  }

  test('owner_id is stamped on insert and on reactivate', () async {
    await dao.mergeDives(['d1', 'd2']);
    expect(await ownerCount('d1'), 1);

    // Unmerge then re-merge must keep owner_id stamped (RLS upload safety).
    await dao.unmerge(generateMergeGroupId(['d1', 'd2']));
    await dao.mergeDives(['d1', 'd2']);
    expect(await ownerCount('d1'), 1);
  });
}
