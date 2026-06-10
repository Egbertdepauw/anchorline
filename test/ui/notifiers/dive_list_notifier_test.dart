import 'dart:io';
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/dive_merge_dao.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/ui/notifiers/dive_list_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' hide SyncStatus;

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late PowerSyncDatabase psDb;
  late DiveDao dao;
  late DiveAnnotationsDao annotationsDao;
  late DiveMergeDao mergeDao;
  late DiveListNotifier notifier;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    psDb = await openPowerSyncForTest();
    dao = DiveDao(db, psDb, FakeSessionSource());
    annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
    mergeDao = DiveMergeDao(db, psDb, FakeSessionSource());
    notifier = DiveListNotifier(dao, annotationsDao, mergeDao);

    for (final num in [711, 712, 718]) {
      final data = File('test/fixtures/dives/dive_$num.bin').readAsBytesSync();
      final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
      final parsed = parser.parse(data);
      final converted = DiveConverter.convert(
        parsed: parsed, dcSerial: 0xB89641E4, dcDiveNumber: num,
        dcModel: ShearwaterModel.petrel3,
      );
      await dao.importDive(converted: converted, rawBlob: data, parserVersion: 1);
    }
  });

  tearDown(() async {
    notifier.dispose();
    await db.close();
  });

  test('loadDives populates dives list', () async {
    await notifier.loadDives();
    expect(notifier.dives, hasLength(3));
  });

  test('dives are ordered by start time descending', () async {
    await notifier.loadDives();
    for (var i = 1; i < notifier.dives.length; i++) {
      expect(notifier.dives[i].startTime, lessThanOrEqualTo(notifier.dives[i - 1].startTime));
    }
  });

  test('groupedByMonth groups dives correctly', () async {
    await notifier.loadDives();
    final groups = notifier.groupedByMonth;
    expect(groups, isNotEmpty);
    for (final key in groups.keys) {
      expect(key, matches(RegExp(r'^[A-Z][a-z]+ \d{4}$')));
    }
  });

  test('getSparklineData returns depth data for a dive', () async {
    await notifier.loadDives();
    final diveId = notifier.dives.first.id;
    final depths = await notifier.getSparklineData(diveId);
    expect(depths, isNotNull);
    expect(depths!.length, greaterThan(0));
  });

  test('getSparklineData caches results', () async {
    await notifier.loadDives();
    final diveId = notifier.dives.first.id;
    final depths1 = await notifier.getSparklineData(diveId);
    final depths2 = await notifier.getSparklineData(diveId);
    expect(identical(depths1, depths2), isTrue);
  });

  test('sequenceByDiveId returns custom userDiveNumber when set', () async {
    await notifier.loadDives();
    // _dives is newest-first; the newest dive gets auto number N (3).
    // Set a custom number on it and verify the override wins.
    final newestId = notifier.dives.first.id;
    await annotationsDao.setUserDiveNumbers({newestId: 99});
    await notifier.loadDives();
    expect(notifier.sequenceByDiveId[newestId], 99);
  });

  test('sequenceByDiveId falls back to auto sequence when no custom number', () async {
    await notifier.loadDives();
    final n = notifier.dives.length;
    // Without any custom numbers, newest dive should be n, oldest should be 1.
    expect(notifier.sequenceByDiveId[notifier.dives.first.id], n);
    expect(notifier.sequenceByDiveId[notifier.dives.last.id], 1);
  });

  test('sequenceByDiveId continues auto numbers from renumbered anchors', () async {
    await notifier.loadDives();
    // _dives is newest-first. Give the two older dives explicit numbers and
    // leave the newest unnumbered: it must continue from the newest anchor
    // (717 + 1 = 718), not fall back to its chronological position (3).
    final oldestId = notifier.dives.last.id;
    final midId = notifier.dives[1].id;
    final newestId = notifier.dives.first.id;
    await annotationsDao.setUserDiveNumbers({oldestId: 716, midId: 717});
    await notifier.loadDives();
    final seq = notifier.sequenceByDiveId;
    expect(seq[oldestId], 716);
    expect(seq[midId], 717);
    expect(seq[newestId], 718,
        reason: 'unnumbered newest dive should continue from the anchor');
  });

  test('selectAll selects all list items and enters selection mode', () async {
    await notifier.loadDives();
    notifier.selectAll();
    expect(notifier.selectionMode, isTrue);
    expect(notifier.selectedDiveIds.length, notifier.listItems.length);
  });

  test('renumberSelected assigns sequential numbers from start', () async {
    await notifier.loadDives();
    notifier.selectAll();
    await notifier.renumberSelected(10);
    // After renumber, selection is cleared and dives are reloaded.
    expect(notifier.selectionMode, isFalse);
    expect(notifier.selectedDiveIds, isEmpty);
    // The 3 dives should now have numbers 10, 11, 12 (oldest → newest).
    final seq = notifier.sequenceByDiveId;
    final numbers = seq.values.toList()..sort();
    expect(numbers, [10, 11, 12]);
    // Verify date ordering: _dives is newest-first, so dives.last is the
    // chronologically oldest and must receive the start number (10);
    // dives.first is the newest and must receive the highest number (12).
    final oldestId = notifier.dives.last.id;
    final newestId = notifier.dives.first.id;
    expect(seq[oldestId], 10,
        reason: 'chronologically oldest dive should receive start number');
    expect(seq[newestId], 12,
        reason: 'chronologically newest dive should receive highest number');
  });

  test('resetNumberingSelected clears custom numbers back to auto', () async {
    await notifier.loadDives();
    // Set a custom number on the newest dive then reset it.
    final id = notifier.dives.first.id;
    await annotationsDao.setUserDiveNumbers({id: 99});
    await notifier.loadDives();
    expect(notifier.sequenceByDiveId[id], 99);

    notifier.enterSelectionMode(id);
    await notifier.resetNumberingSelected();
    // Auto sequence: newest dive = length of list (3).
    expect(notifier.sequenceByDiveId[id], notifier.dives.length);
    expect(notifier.selectionMode, isFalse);
  });
}
