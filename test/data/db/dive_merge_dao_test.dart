import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_merge_dao.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  late AppDatabase db;
  late DiveMergeDao dao;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = (await openDiveMergeDaoForTest(db)).dao;
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
}
