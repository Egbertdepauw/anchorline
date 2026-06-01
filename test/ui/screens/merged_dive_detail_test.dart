import 'dart:io';

import 'package:ccrlogger/analysis/merge/merged_sample_builder.dart';
import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/dive_detail_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  // Regression for the post-merge crash: opening a merged dive threw
  // "Unsupported operation: Infinity or NaN toInt" inside _buildStatsRow
  // (NaN surface-gap samples reaching minAvgMax / computeOtu / the deco
  // replay), which blanked the entire Details tab below the chart.
  testWidgets('merged dive detail renders without NaN crash + shows #seq',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    late final int mergedDurationSeconds;
    await tester.runAsync(() async {
      final ps = await openPowerSyncForTest();
      final session = FakeSessionSource()..setUserId('u');
      final dao = DiveDao(db, ps, session);
      // Two real recorded dives. They are far apart in time, so the builder's
      // display-cap kicks in — exactly the path that produced the bad data.
      for (final num in [716, 717]) {
        final data =
            File('test/fixtures/dives/dive_$num.bin').readAsBytesSync();
        final parsed =
            ShearwaterDiveParser(model: ShearwaterModel.petrel3).parse(data);
        final converted = DiveConverter.convert(
          parsed: parsed,
          dcSerial: 0xB89641E4,
          dcDiveNumber: num,
          dcModel: ShearwaterModel.petrel3,
        );
        await dao.importDive(
            converted: converted, rawBlob: data, parserVersion: 1);
      }
      final all = await dao.getAllDives()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      final members = <MergeMember>[];
      for (final d in all) {
        members.add((dive: d, samples: (await dao.getSamples(d.id))!));
      }
      final merged = buildMergedDive(mergedId: 'grp', members: members);
      mergedDurationSeconds = merged.dive.durationSeconds;

      final annDao = DiveAnnotationsDao(ps, session);
      final equipDao = EquipmentDao(db, ps, session);
      // Pre-merge annotation on the earliest member: it must surface on the
      // merged view (the user's "annotations disregarded after merge" report).
      final earliestId = all.first.id;
      final now = DateTime.now();
      await annDao.upsert(DiveAnnotation(
        diveId: earliestId,
        siteName: 'Test Reef',
        createdAt: now,
        updatedAt: now,
      ));
      await tester.pumpWidget(MaterialApp(
        home: DiveDetailScreen(
          dive: merged.dive,
          preloadedSamples: merged.samples,
          dao: dao,
          annotationsDao: annDao,
          equipmentDao: equipDao,
          settingsNotifier: SettingsNotifier(),
          annotationsDiveId: earliestId,
          sequenceNumber: 716,
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();

    // The crash surfaced as a layout-time exception; assert there is none.
    expect(tester.takeException(), isNull);
    // The capped gap keeps both dives' data: synthetic dur = sum of members.
    expect(mergedDurationSeconds, 3620 + 1367);
    // Numbering: title uses the passed CCRLog sequence number, not #729.
    expect(find.textContaining('#716'), findsWidgets);
    expect(find.textContaining('#729'), findsNothing);
    // The stats row built (it previously crashed before any tile rendered).
    // StatTile renders its label uppercased.
    expect(find.textContaining('CNS'), findsWidgets);
    // The earliest member's annotation surfaces on the merged view.
    expect(find.textContaining('Test Reef'), findsWidgets);
  });
}
